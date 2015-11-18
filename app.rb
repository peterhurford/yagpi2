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
  Api.receive_hook_and_return_data!(JSON.parse(request.body.read))
end
