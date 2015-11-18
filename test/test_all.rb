require "minitest/autorun"
require "rack/test"
require "pry"
require File.expand_path "../../app.rb", __FILE__

ENV["RACK_ENV"] = "test"


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
      "action" => "test",
      "pull_request" => {
        "body" => "test",
        "head" => { "ref" => "test" },
        "html_url" => "test",
        "user" => { "login" => "test" }
      }
    }
  end


  def test_ping
    get "/ping"
    assert(last_response.ok?)
    assert_equal(Api.receive_ping.to_json, last_response.body)
  end

  def test_hook_returns_ping
    post "/github_hook", '{ "zen": "Responsive is better than fast." }'
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
        params["pull_request"]["head"]["ref"] = nil
      end
      assert_error(StandardError, "No branch") { Api.validate_payload(no_branch_params) }
    end
  end

  def test_params_with_no_pr_url_does_not_validate
    with_errors do
      no_pr_url_params = complete_params.tap do |params|
        params["pull_request"]["html_url"] = nil
      end
      assert_error(StandardError, "No PR URL") { Api.validate_payload(no_pr_url_params) }
    end
  end

  def test_params_with_no_author_does_not_validate
    with_errors do
      no_author_params = complete_params.tap do |params|
        params["pull_request"]["user"]["login"] = nil
      end
      assert_error(StandardError, "No author") { Api.validate_payload(no_author_params) }
    end
  end

  def test_that_it_can_find_a_pivotal_url_in_a_body
    with_errors do
      assert_equal("1234567", Pivotal.find_pivotal_id("Blah blah 1234567 blah blah", "branch_name_here"))
    end
  end

  def test_that_it_can_find_a_pivotal_url_in_a_branch
    with_errors do
      assert_equal("1234567", Pivotal.find_pivotal_id("Blah blah blah blah", "branch_name_here_1234567"))
    end
  end

  def test_that_it_handles_a_missing_pivotal_id
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        assert_equal("nag", Api.handle_missing_pivotal_id(complete_params)["pivotal_action"])
      end
    end
  end

  def test_that_it_finishes_an_open_pr
    opening_params = complete_params.tap do |params|
      params["action"] = "opened"
      params["pull_request"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          assert_equal("finish", Api.receive_hook_and_return_data!(opening_params)["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_delivers_a_closed_pr
    closing_params = complete_params.tap do |params|
      params["action"] = "closed"
      params["pull_request"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          assert_equal("deliver", Api.receive_hook_and_return_data!(closing_params)["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_ignores_otherwise
    ignorable_params = complete_params.tap do |params|
      params["action"] = "resynch"
      params["pull_request"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          assert_equal("ignore", Api.receive_hook_and_return_data!(ignorable_params)["pivotal_action"])
        end
      end
    end
  end

  def test_pivotal_post_is_parsable
    assert(JSON.parse(Pivotal.pivotal_post_message("108405812", "test.com", "peterhurford", "finishes")).is_a?(Hash))
  end
end

