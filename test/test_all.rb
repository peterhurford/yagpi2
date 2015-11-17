require "minitest/autorun"
require "rack/test"
require File.expand_path "../../app.rb", __FILE__

class TestTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_ping
    get "/ping"
    assert(last_response.ok?)
    assert_equal(Api.receive_ping.to_json, last_response.body)
  end
end

