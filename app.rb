require "sinatra"
require "sinatra/activerecord"
require "json"

require "./lib/api"

set :bind, '0.0.0.0'

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
  Api.receive_hook_and_return_data!(JSON.parse(payload)).to_json
end

def secret_token
  @token ||= ENV["SECRET_TOKEN"]
end

def verify_signature(payload)
  Api.error!('No secret token', 500) unless secret_token.present?
  signature = 'sha1=' +
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), secret_token, payload)

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
