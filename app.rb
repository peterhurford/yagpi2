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
  Api.error!('No payload', 500) unless payload.present?
  Api.receive_hook_and_return_data!(JSON.parse(payload))
end
