require "sinatra"
require "./lib/hook"

get "/ping" do
  "OK"
end

post '/github_hook' do
  receive_hook_and_return_data!(params)
end
