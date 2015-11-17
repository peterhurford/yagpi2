require "sinatra"
require "json"

require "./lib/hook"

get "/" do
  receive_ping.to_json
end

get "/ping" do
  receive_ping.to_json
end

post '/github_hook' do
  receive_hook_and_return_data!(params)
end
