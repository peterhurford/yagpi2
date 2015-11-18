require "sinatra"
require "sinatra/activerecord"
require "json"

require "./lib/pivotal"
require "./lib/github"
require "./lib/api"

get "/" do
  Api.receive_ping.to_json
end

get "/ping" do
  Api.receive_ping.to_json
end

post '/github_hook' do
  payload = request.body.read
  verify_signature(payload) unless ENV["RACK_ENV"] == "test"
  Api.error!('No payload', 500) unless payload.present?
  output = Api.receive_hook_and_return_data!(JSON.parse(payload)).to_json
  Api.error!(output, 101)
end

def verify_signature(payload)
  signature = 'sha1=' +
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'),
                            ENV['SECRET_TOKEN'], payload)

  unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
    return halt 500, "Signatures didn't match!" 
  end
end

error do
  {
    message: env['sinatra.error'].message,
    backtrace: env['sinatra.error'].backtrace
  }.to_json
end
