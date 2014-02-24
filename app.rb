require "bundler/setup"
require "sinatra"
require "sinatra/multi_route"
require "data_mapper"
require "twilio-ruby"
require 'twilio-ruby/rest/messages'
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
DataMapper::setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/jreyes')

class VerifiedUser
  include DataMapper::Resource

  property :id, Serial
  property :phone_number, String, :length => 30, :required => true
  property :code, String, :length => 10, :unique => true
  property :name, String
  property :status, Enum[ :new, :naming, :shirt, :shoes, :watch, :glasses, :playing, :targeted, :verifying, :confirming, :injured, :healed, :striking], :default => :new
  property :misses, Integer, :default => 0
  property :wins, Integer, :default => 0
  property :losses, Integer, :default => 0
  property :dodges, Integer, :default => 0
  property :identifier, String
  property :shoes, String, :default => 'black'
  property :shirt, String, :default => 'blue'
  property :watch, Enum['yes', 'no'], :default => 'no'
  property :glasses, Enum['yes', 'no'], :default => 'no'
  property :injured, Time, :default => Time.now

  validates_with_method :shoes, :method => :check_shoes
  validates_with_method :shirt, :method => :check_shirt
  
  def check_shirt
    colors = ['white', 'black', 'gray', 'blue', 'green', 'red', 'orange', 'brown', 'yellow', 'purple']
    if colors.include?(@shirt)
      return true
    else
      return [false, "That color is not a common color. Think more rainbowy."]
    end
  end

  def check_shoes
    colors = ['white', 'black', 'gray', 'blue', 'green', 'red', 'orange', 'brown', 'yellow', 'purple']
    if colors.include?(@shoes)
      return true
    else
      return [false, "That color is not a common color. Think more rainbowy."]
    end
  end

  has n, :targets

end

class Target
  include DataMapper::Resource

  property :id, Serial
  property :code, String, :length => 6
  property :name, String
  property :phone_number, String, :length => 30
  property :hit, Enum['yes', 'no'], :default => 'no'
  property :proof, Enum['none', 'shirt', 'shoes', 'watch', 'glasses'], :default => 'none'
  property :attack, Text

  belongs_to :verified_user

end
DataMapper.finalize
DataMapper.auto_upgrade!

before do
  @ronin_number = ENV['RONIN_NUMBER']
  @client = Twilio::REST::Client.new ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']
  @mmsclient = @client.accounts.get(ENV['TWILIO_SID'])

  if params[:error].nil?
    @error = false
  else
    @error = true
  end

end

get '/dispatch/?' do
  # Decide what do based on status and body
  @phone_number = Sanitize.clean(params[:From])
  @body = params[:Body].downcase
  # Find the user associated with this number if there is one
  @user = VerifiedUser.first(:phone_number => @phone_number)

  if @user.nil?
    code = createCode()
    puts code
    @user = createUser(@phone_number, code)
    if not @user.valid?
      puts @user.valid?
      new_code = createCode()
      @user = createUser(@phone_number, new_code)
    end
  end

  begin
    status = @user.status
    puts status
    case status
    # Setup the player details
    when :new
      output = "Welcome to the game of SMS Ronin. To begin playing we need to ask you a few questions. First what is your Samurai nickname?"
      message = @mmsclient.messages.create(
        :from => 'TWILIO',
        :to => @phone_number,
        :body => "SMS Ronin",
        :media_url => "http://cl.ly/image/0i0928403z2G/ronin-card.jpg",
      ) 
      puts message.to
      @user.update(:status => 'naming')
    # Get User Name
    when :naming
      if @user.name.nil?
        @user.name = @body
        @user.save
        output = "We have your nickname as #{@body}. Is this correct? [yes] or [no]?"
      else
        if @body == 'yes'
          output = "Great! Next in order for other players to recognize you we need to ask you a few more questions. First, what color is your shirt?"
          @user.update(:status => 'shirt')
        else
          output = "Okay Samurai. What is your nickname?"
          @user.update(:name => nil)
        end
      end
    # Get shirt color
    when :shirt
      @user.update(:shirt => @body)
      if @user.valid?
        output = "Ok Hai! We've got your shirt color. Now what color are your shoes?"
        @user.update(:status => 'shoes')
      else
        output = @user.errors.on(:shirt)
      end
    # Get shoe color
    when :shoes
      @user.update(:shoes => @body)
      if @user.valid?
        output = "Ok Hai! We've got your shoe color. Now are you wearing a watch? [yes] or [no]"
        @user.update(:status => 'watch')
      else
        output = @user.errors.on(:shoes)
      end
    # Wearing a watch?
    when :watch
      output = "Almost done. Now are you wearing glasses? [yes] or [no]"
      @user.update(:watch => @body, :status => 'glasses')
    # Wearing glasses?
    when :glasses
      userCode = @user.code
      output = "You are ready to play. In order to start your game simply display your code somewhere on your person. Your code is: #{userCode}. In order to eliminate other players just text in their code. Remember sometimes the best way to win a game, is to pretend there is no game. Begin!"
      @user.update(:glasses => @body, :status => 'playing')
    # If we get a text now it's a hex code
    when :playing
      i = rand(0..3)
      a = rand(0.._KILLWORDS.length)
      questions = ["What color was the Ronin's shirt?", "What color were the Ronin's shoes?", "Was this Ronin wearing a watch?", "Was this Ronin wearing glasses?"]
      proof = ["shirt", "shoes", "watch", "glasses"]
      q = questions[i]
      targetProof = proof[i]
      targetCode = @body
      @target = VerifiedUser.first(:code => targetCode)
      res = "Target: #{@target}, Injured Time: #{@user.injured} "
      puts res
      currentTime = Time.now
      if @user.injured > currentTime
        output = "Looks like you are still injured. Come back once you've healed."
      else
        if @target.nil?
          output = "Oops! Unfortunately that code does not identify another player. Try again."
        else
          # make sure the player hasn't submitted their own code
          if not @target.code == @user.code
            @targetPhone = @target.phone_number
            @targetName = @target.name
            # check if target has already been assigned to user

            @userTarget = @user.targets.first(:code => targetCode)

            # if target hasn't been assigned, assign it.
            if @userTarget.nil?
              targetAttack = _KILLWORDS[a]
              hit = _HITWORDS[a]
              @userTarget = @user.targets.create(:code => targetCode, :phone_number => @targetPhone, :name => @targetName, :proof => targetProof, :attack => hit)
              @user.save
              
              output = "You are attempting to #{targetAttack} #{@targetName}. To verify you met #{@targetName}, answer this question. #{q}"
              @user.update(:status => 'verifying')

            # if target has been assigned deny assassin attempt
            else
              output = "Unfortunately you have already targeted #{@targetName}. Time to find new target."
            end
          else
            output = "Supoku this early in the game? Are you sure you want to stop playing? [yes] or [no]"
          end
        end
      end
    when :verifying
      @userTarget = @user.targets.last
      targetPhone = @userTarget.phone_number
      targetProof = @userTarget.proof
      puts "phone: #{targetPhone}, proof: #{targetProof} "
      @target = VerifiedUser.first(:phone_number => targetPhone)
      answer = @target[targetProof]
      attacked = @userTarget.attack
      # if the answer is correct, award the victor
      if @body == answer
        # Punish the loser
        injuredTime = Time.now + 5*60
        targetLosses = @target.losses + 1
        # ToDo: add place in the leaderboard to message
        @message = "Oh no! You were just #{attacked} by #{@user.name}. You are now injured, which means you can not attack for 5 minutes."
        puts @message
        @target.update(:losses => targetLosses, :status => 'playing', :injured => injuredTime)
        
        # Award the winner
        userWins = @user.wins + 1
        @user.update(:wins => userWins, :status => 'playing')
        output = "Well done Samurai. #{@target.name} was just #{attacked} by you. [ wins: #{userWins} ] [ losses: #{@user.losses} ]"
        puts output
      else
        targetDodges = @target.dodges + 1
        @message = "Whew! You were nearly just #{attacked} by #{@user.name}. You now have #{targetDodges} dodges."
        @target.update(:dodges => targetDodges)

        # user is injured due to her miss
        userMisses = @user.misses + 1
        @user.update(:misses => userMisses, :status => 'playing')
        output = "Ooh it looks like you just missed #{@target.name}. Better next time Samurai."
      end
      sendMessage(@ronin_number, @target.phone_number, @message)
      puts "ronin_n: #{@ronin_number}"
    else
      output = "doh!"
    end
  rescue
    output = "there was a user.status error."
  end

  if params['SmsSid'] == nil
    erb :index, :locals => {:msg => output}
  else
    response = Twilio::TwiML::Response.new do |r|
      r.Sms output
    end
    response.text
  end
end

def createCode()
  hex = ('a'..'z').to_a.shuffle[0,4].join
  return hex
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

get '/users/' do
  @users = VerifiedUser.all
  puts @users
  haml :users
end