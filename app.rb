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
  begin
    request.body.rewind
    payload = JSON.parse(request.body.read)
    verify_signature(payload) unless ENV["RACK_ENV"] == "test"
    Api.error!('No payload', 500) unless payload.present?
    Api.receive_hook_and_return_data!(payload)
  rescue exception => e
    Api.error!(e, 500)
  end
end

def verify_signature(payload)
  signature = 'sha1=' +
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'),
                            ENV['SECRET_TOKEN'], payload)

  unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
    return halt 500, "Signatures didn't match!" 
  end
end
