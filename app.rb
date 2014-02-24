require "bundler/setup"
require "sinatra"
require "sinatra/multi_route"
require "data_mapper"
require "twilio-ruby"
require 'twilio-ruby/rest/messages'
require 'iron_worker_ng'
require "sanitize"
require "erb"
require "rotp"
require "haml"
include ERB::Util

_KILLWORDS = ['decimate', 'kind of obliterate', 'strike', 'cut', 'soul-crush', 'cut down with a tiny machete', 'sword strike', 'throw a ninja star at', 'stab a little bit', 'hit with a blunt object', 'jump out of a bush and poke', 'kick the shins of', 'karate chop!', 'make an example of', 'throw a rabid gerbil at', 'spray a deadly love potion on', 'cast a super secret samurai spell on', 'dump deadly orange gatorade on', 'poke with stick covered in jellyfish', 'release the entire North Korean army at', 'trip with a lazy dog', 'toilet-paper the samurai hut of']
_HITWORDS = ['decimated', 'kind of obliterated', 'struck', 'cut', 'soul-crushed', 'cut down with a tiny machete', 'struck with a sword', 'hit with a ninja star', 'stabbed a little bit', 'hit with a blunt object', 'poked from a bush', 'kicked in the shins', 'karate chopped!', 'made an example of', 'hit with a rabid gerbil thrown', 'sprayed with a deadly love potion', 'blinded by a secret samurai spell', 'dumped upon with deadly orange gatorade', 'poked with a stick covered in jellyfish', 'badly bruised by the entire force of the North Korean army lead', 'tripped with a lazy dog', 'subject to your samurai hut being toilet-papered']
set :static, true
set :root, File.dirname(__FILE__)

DataMapper::Logger.new(STDOUT, :debug)
DataMapper::setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/rosie')

class VerifiedUser
  include DataMapper::Resource

  property :id, Serial
  property :code, String, :length => 10
  property :name, String
  property :phone_number, String, :length => 30
  property :verified, Boolean, :default => false
  property :status, Enum[ 'adding', 'verifying', 'date' ], :default => 'adding'

  has n, :leftovers

end

class Leftover
  include DataMapper::Resource

  property :id, Serial
  property :body, Text
  property :time, DateTime
  property :name, String

  belongs_to :verified_user

end
DataMapper.finalize
DataMapper.auto_upgrade!

before do
  @twilio_number = 17603034118
  @client = Twilio::REST::Client.new ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']
  # @mmsclient = @client.accounts.get(ENV['TWILIO_SID'])
  @iw = IronWorkerNG::Client.new

  if params[:error].nil?
    @error = false
  else
    @error = true
  end

end

# Register a subscriber through the web and send verification code
route :get, :post, '/register' do
  @phone_number = Sanitize.clean(params[:phone_number])
  if @phone_number.empty?
    redirect to("/?error=1")
  end

  begin
    if @error == false
      user = VerifiedUser.create(
        :name => params[:name],
        :phone_number => @phone_number
      )

      if user.verified == true
        @phone_number = url_encode(@phone_number)
        redirect to("/verify?phone_number=#{@phone_number}&verified=1")
      end
      totp = ROTP::TOTP.new("cleanthefridge")
      code = totp.now
      user.code = code
      user.save

      sendMessage(@twilio_number, @phone_number, "Your verification code is #{code}")
    end
    erb :register
  rescue
    redirect to("/?error=2")
  end
end

# Endpoint for verifying code was correct
route :get, :post, '/verify' do

  @phone_number = Sanitize.clean(params[:phone_number])

  @code = Sanitize.clean(params[:code])
  user = VerifiedUser.first(:phone_number => @phone_number)
  if user.verified == true
    @verified = true
  elsif user.nil? or user.code != @code
    @phone_number = url_encode(@phone_number)
    redirect to("/register?phone_number=#{@phone_number}&error=1")
  else
    user.verified = true
    user.save
  end
  erb :verified
end

get '/rosie/?' do
  # Decide what do based on status and body
  @phone_number = Sanitize.clean(params[:From])
  puts @phone_number
  @body = params[:Body].downcase
  # Find the user associated with this number if there is one
  @user = VerifiedUser.first(:phone_number => @phone_number)
  @now = DateTime.now

  case @user.status
  when 'adding'
    leftover = @user.leftovers.create(
        :name => @body,
        :time => @now,
      )
    @scheduleMsg = {
      :twilio => {
        :sid => ENV['TWILIO_ACCOUNT_SID'], 
        :token => ENV['TWILIO_AUTH_TOKEN'],
        :from => @twilio_number,
      },
      :to => @phone_number,
      :body => "Reminder from LeftOvers. 1 day left to use #{@body}.",
    }
    @iw.tasks.create("sms", @scheduleMsg, {:delay=>10})
  end
  Twilio::TwiML::Response.new do |r|
    r.Message "Great #{@user.name}. We've logged that you've added #{@body} to your fridge."
  end.text
end

def sendMessage(from, to, body)
  message = @client.account.messages.create(
    :from => from,
    :to => to,
    :body => body
  )
  puts message.to
end

def createUser(phone_number, code)
  user = VerifiedUser.create(
    :phone_number => phone_number,
    :code => code,
  )
  user.save
  return user
end

get "/" do
  haml :index
end
get "/signup" do
  haml :signup
end
get '/users/' do
  @users = VerifiedUser.all
  puts @users
  erb :users
end