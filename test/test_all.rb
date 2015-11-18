require "minitest/autorun"
require "rack/test"
require "pry"
require File.expand_path "../../app.rb", __FILE__


class TestTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def assert_error(exception, message, &block)
    block.call
  rescue exception => e
    assert_match(message, e.message)
  end

  def with_errors(&block)
    Api.set_raises_flag!
    block.call
    Api.unset_raises_flag!
  end

  def complete_params
    {
      "body" => "test",
      "head" => { "ref" => "test" },
      "action" => "test",
      "html_url" => "test",
      "user" => { "login" => "test" }
    }
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

  def test_that_params_validate
    assert(Api.validate_payload(complete_params).is_a?(Hash))
  end

  def test_params_with_no_action_does_not_validate
    with_errors do
      no_action_params = complete_params.tap do |params|
        params["action"] = nil
      end
      assert_error(StandardError, "No action") { Api.validate_payload(no_action_params) }
    end
  end

  def test_params_with_no_branch_does_not_validate
    with_errors do
      no_branch_params = complete_params.tap do |params|
        params["head"]["ref"] = nil
      end
      assert_error(StandardError, "No branch") { Api.validate_payload(no_branch_params) }
    end
  end

  def test_params_with_no_pr_url_does_not_validate
    with_errors do
      no_pr_url_params = complete_params.tap do |params|
        params["html_url"] = nil
      end
      assert_error(StandardError, "No PR URL") { Api.validate_payload(no_pr_url_params) }
    end
  end

  def test_params_with_no_author_does_not_validate
    with_errors do
      no_author_params = complete_params.tap do |params|
        params["user"]["login"] = nil
      end
      assert_error(StandardError, "No author") { Api.validate_payload(no_author_params) }
    end
  end

  def test_that_it_can_find_a_pivotal_url_in_a_body
    assert_equal("1234567", Pivotal.find_pivotal_id("Blah blah 1234567 blah blah", "branch_name_here"))
  end

  def test_that_it_can_find_a_pivotal_url_in_a_branch
    assert_equal("1234567", Pivotal.find_pivotal_id("Blah blah blah blah", "branch_name_here_1234567"))
  end
end

