# Inputs
#
#   twilio:
#     sid: your twilio sid
#     token: your twilio token
#     from: your twilio phone number
#   to: "the phone number to send to"
#   body: "The message to send"
#

require 'twilio-ruby'

@config = YAML.load_file("config.yml")

sid = @config['twilio']['sid']
token = @config['twilio']['token']
from = @config['twilio']['from']
to = params[:to]
body = params[:body]
puts to

# set up a client to talk to the Twilio REST API
@client = Twilio::REST::Client.new sid, token

if to
# And finally, send the message
  r = @client.account.sms.messages.create(
      :from => from,
      :to => to,
      :body => body
  )
  p r
end
