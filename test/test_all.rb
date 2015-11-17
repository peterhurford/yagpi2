require "minitest/autorun"
require "rack/test"
require "pry"
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

  def test_hook_returns_ping
    post "/github_hook", { zen: "Responsive is better than fast." }
    assert(last_response.ok?)
    assert_equal(Api.receive_ping.to_json, last_response.body)
  end

  def test_hook_errors_with_no_payload
    post "/github_hook"
    refute(last_response.ok?)
    assert_equal(500, JSON.parse(last_response.body)["error"])
  end
end

