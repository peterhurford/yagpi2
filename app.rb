require "sinatra"
require "./lib/hook"

get "/" do
  receive_ping
end

get "/ping" do
  receive_ping
end

post '/github_hook' do
  receive_hook_and_return_data!(params)
end
