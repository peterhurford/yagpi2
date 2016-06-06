require "./app"
require "minitest/autorun"
require "rack/test"
require "pry"

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

  def complete_pr_params
    {
      "action" => "test",
      "pull_request" => {
        "body" => "test",
        "head" => { "ref" => "test" },
        "html_url" => "test",
        "user" => { "login" => "test" },
        "merged" => true
      }
    }
  end

  def complete_issue_params
    complete_pr_params.tap do |params|
      params["issue"] = params["pull_request"]
      params["pull_request"] = nil
    end
  end


  def test_ping
    get "/ping"
    assert(last_response.ok?)
    assert_equal(Api.receive_ping.to_json, last_response.body)
  end

  def test_is_github_ping
    assert(Github.is_github_ping?({"zen" => "zen'd!"}))
    refute(Github.is_github_ping?({"no_zen" => "no zen 4 u!"}))
  end

  def test_is_pull_request_action
    assert(Github.is_pull_request_action?({"pull_request" => "got your action right here!"}))
    refute(Github.is_pull_request_action?({"issue" => "this is an issue!"}))
  end

  def test_is_pull_request_action
    assert(Github.is_issue_action?({"issue" => "this is an issue!"}))
    refute(Github.is_issue_action?({"pull_request" => "got your action right here!"}))
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

  def test_that_pull_request_params_validate
    assert(Api.validate_pull_request_payload(complete_pr_params).is_a?(Hash))
  end

  def test_that_malformed_payload_does_not_validate
    with_errors do
      assert_error(StandardError, "Malformed payload") {
        Api.validate_pull_request_payload({}) }
      assert_error(StandardError, "Malformed payload") {
        Api.validate_issue_payload({}) }
    end
  end

  def test_that_issue_params_validate
    assert(Api.validate_issue_payload(complete_issue_params).is_a?(Hash))
  end

  def test_params_with_no_action_does_not_validate
    with_errors do
      pr_no_action_params = complete_pr_params.tap do |params|
        params["action"] = nil
      end
      issue_no_action_params = complete_issue_params.tap do |params|
        params["action"] = nil
      end
      assert_error(StandardError, "No action") {
        Api.validate_pull_request_payload(pr_no_action_params) }
      assert_error(StandardError, "No action") {
        Api.validate_issue_payload(issue_no_action_params) }
    end
  end

  def test_params_with_no_branch_does_not_validate
    with_errors do
      no_branch_params = complete_pr_params.tap do |params|
        params["pull_request"]["head"]["ref"] = nil
      end
      assert_error(StandardError, "No branch") {
        Api.validate_pull_request_payload(no_branch_params) }
    end
  end

  def test_params_with_no_url_does_not_validate
    with_errors do
      pr_no_url_params = complete_pr_params.tap do |params|
        params["pull_request"]["html_url"] = nil
      end
      issue_no_url_params = complete_issue_params.tap do |params|
        params["issue"]["html_url"] = nil
      end
      assert_error(StandardError, "No URL") {
        Api.validate_pull_request_payload(pr_no_url_params) }
      assert_error(StandardError, "No URL") {
        Api.validate_issue_payload(issue_no_url_params) }
    end
  end

  def test_params_with_no_author_does_not_validate
    with_errors do
      pr_no_author_params = complete_pr_params.tap do |params|
        params["pull_request"]["user"]["login"] = nil
      end
      issue_no_author_params = complete_pr_params.tap do |params|
        params["pull_request"]["user"]["login"] = nil
      end
      assert_error(StandardError, "No author") {
        Api.validate_pull_request_payload(pr_no_author_params) }
      assert_error(StandardError, "No author") {
        Api.validate_pull_request_payload(issue_no_author_params) }
    end
  end

  def test_that_it_can_find_a_pivotal_url_in_a_body
    with_errors do
      assert_equal("1234567",
        Pivotal.find_pivotal_id("Blah blah #1234567 blah blah", "branch_name_here"))
      assert_equal("1234567",
        Pivotal.find_pivotal_id("Blah blah show/1234567 blah blah", "branch_name_here"))
    end
  end

  def test_that_it_can_find_a_pivotal_url_in_a_branch
    with_errors do
      assert_equal("1234567",
         Pivotal.find_pivotal_id("Blah blah blah blah", "branch_name_here_1234567"))
    end
  end

  def test_that_it_ignores_fake_ids_in_a_body
    with_errors do
      assert_equal("9876543",
        Pivotal.find_pivotal_id("Fake id: 1234567, Real id: #9876543 blah blah", "branch_name_here"))
      assert_equal("9876543",
        Pivotal.find_pivotal_id("Fake id: 1234567, Real id: show/9876543 blah blah", "branch_name_here"))
    end
  end

  def test_ignore
    with_errors do
      assert_equal("ignore", Api.ignore(complete_pr_params, "1234567")["pivotal_action"])
    end
  end

  def test_api_results
    with_errors do
      assert_equal("finished",
        Api.api_results(complete_pr_params, "1234567", "finished")["pivotal_action"])
    end
  end

  def test_that_it_finishes_an_open_pr
    opening_params = complete_pr_params.tap do |params|
      params["action"] = "opened"
      params["pull_request"]["body"] = "#1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          output = Api.receive_hook_and_return_data!(opening_params)
          assert_equal("pull_request", output["type"])
          assert_equal("finish", output["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_finishes_an_reopened_pr
    opening_params = complete_pr_params.tap do |params|
      params["action"] = "reopened"
      params["pull_request"]["body"] = "#1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          output = Api.receive_hook_and_return_data!(opening_params)
          assert_equal("pull_request", output["type"])
          assert_equal("finish", output["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_handles_a_missing_pivotal_id
    opening_params = complete_pr_params.tap do |params|
      params["action"] = "opened"
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          output = Api.receive_hook_and_return_data!(opening_params)
          assert_equal("pull_request", output["type"])
          assert_equal("nagfinish", output["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_delivers_a_closed_and_merged_pr
    closing_params = complete_pr_params.tap do |params|
      params["action"] = "closed"
      params["pull_request"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          assert_equal("deliver",
            Api.receive_hook_and_return_data!(closing_params)["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_delivers_a_closed_issue
    closing_params = complete_issue_params.tap do |params|
      params["action"] = "closed"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Pivotal.stub(:deliver!, MiniTest::Mock.new) do
        Pivotal.stub(:accept!, MiniTest::Mock.new) do
          assert_equal("deliver",
            Api.receive_hook_and_return_data!(closing_params)["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_ignores_a_closed_and_unmerged_pr
    closing_params = complete_pr_params.tap do |params|
      params["action"] = "closed"
      params["pull_request"]["merged"] = false
      params["pull_request"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          assert_equal("ignore",
            Api.receive_hook_and_return_data!(closing_params)["pivotal_action"])
        end
      end
    end
  end

  def test_that_it_ignores_otherwise
    ignorable_params = complete_pr_params.tap do |params|
      params["action"] = "resynch"
      params["pull_request"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Github.stub(:nag_for_a_pivotal_id!, MiniTest::Mock.new) do
        Pivotal.stub(:change_story_state!, MiniTest::Mock.new) do
          assert_equal("ignore",
            Api.receive_hook_and_return_data!(ignorable_params)["pivotal_action"])
        end
      end
    end
  end


  def test_that_it_creates_a_bug_on_issue_open
    closing_params = complete_issue_params.tap do |params|
      params["action"] = "opened"
    end
    with_errors do
      Github.stub(:post_pivotal_link_on_issue!, MiniTest::Mock.new) do
        Pivotal.stub(:create_a_bug!, MiniTest::Mock.new) do
          assert_equal("create",
           Api.receive_hook_and_return_data!(closing_params)["pivotal_action"])
        end
      end
    end

  end


  def test_that_it_assigns
    assigning_params = complete_issue_params.tap do |params|
      params["action"] = "assigned"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
      params["issue"]["assignee"] = { "login" => "RolandFreedom" }
    end
    with_errors do
      Pivotal.stub(:assign!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(assigning_params)
        assert_equal("assign", output["pivotal_action"])
        assert_equal("RolandFreedom", output["assignee"])
      end
    end
  end

  def test_that_it_reassigns
    assigning_params = complete_issue_params.tap do |params|
      params["action"] = "assigned"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
      params["issue"]["assignee"] = { "login" => "RolandFreedom" }
    end
    reassigning_params = complete_issue_params.tap do |params|
      params["action"] = "assigned"
      params["issue"]["body"] = "1234567"
      params["issue"]["assignee"] = { "login" => "CarlCarlton" }
    end
    with_errors do
      Pivotal.stub(:assign!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(assigning_params)
        assert_equal("assign", output["pivotal_action"])
        assert_equal("RolandFreedom", output["assignee"])
        output = Api.receive_hook_and_return_data!(reassigning_params)
        assert_equal("assign", output["pivotal_action"])
        assert_equal("CarlCarlton", output["assignee"])
      end
    end
  end

  def test_that_it_unassigns
    unassigning_params = complete_issue_params.tap do |params|
      params["action"] = "unassigned"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Pivotal.stub(:assign!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(unassigning_params)
        assert_equal("assign", output["pivotal_action"])
        assert_equal(nil, output["assignee"])
      end
    end
  end

  def test_that_it_labels
    labeling_params = complete_issue_params.tap do |params|
      params["action"] = "labeled"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
      params["issue"]["labels"] = [{"name" => "label"}]
    end
    with_errors do
      Pivotal.stub(:label!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(labeling_params)
        assert_equal("label", output["pivotal_action"])
        assert_equal("label", output["labels"])
      end
    end
  end

  def test_that_it_relabels
    labeling_params = complete_issue_params.tap do |params|
      params["action"] = "labeled"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
      params["issue"]["labels"] = [{"name" => "label"}]
    end
    relabeling_params = complete_issue_params.tap do |params|
      params["action"] = "labeled"
      params["issue"]["body"] = "1234567"
      params["issue"]["labels"] = [{"name" => "new_label"}]
    end
    with_errors do
      Pivotal.stub(:label!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(labeling_params)
        assert_equal("label", output["pivotal_action"])
        assert_equal("label", output["labels"])
        output = Api.receive_hook_and_return_data!(relabeling_params)
        assert_equal("label", output["pivotal_action"])
        assert_equal("new_label", output["labels"])
      end
    end
  end

  def test_that_it_unlabels
    unlabeling_params = complete_issue_params.tap do |params|
      params["action"] = "unlabeled"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
    end
    with_errors do
      Pivotal.stub(:label!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(unlabeling_params)
        assert_equal("label", output["pivotal_action"])
        assert_equal(nil, output["labels"])
      end
    end
  end

  def test_that_it_multi_labels
    labeling_params = complete_issue_params.tap do |params|
      params["action"] = "labeled"
      params["issue"]["body"] = "1234567"  # Add a Pivotal ID
      params["issue"]["labels"] = [{"name" => "label"}, { "name" => "label2" }]
    end
    with_errors do
      Pivotal.stub(:label!, MiniTest::Mock.new) do
        output = Api.receive_hook_and_return_data!(labeling_params)
        assert_equal("label", output["pivotal_action"])
        assert_equal("label, label2", output["labels"])
      end
    end
  end
end
