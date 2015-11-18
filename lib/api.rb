class Api
  def self.receive_ping
    { "status" => "ping_received" }
  end


  #TODO: Move error handling
  @@raises = false

  def self.set_raises_flag!
    @@raises = true
  end

  def self.unset_raises_flag!
    @@raises = false
  end

  def self.halt!(*response)
    throw(:halt, response)
  end

  def self.error!(error_message, error_type)
    if @@raises
      raise StandardError.new(error_message)
    else
      halt!(error_type,
        {'Content-Type' => 'application/json'}, {
          error: error_type,
          message: error_message
        }.to_json)
    end
  end


  def self.validate_payload(payload)
    validated_payload = {
      "github_body" => payload["pull_request"]["body"],
      "github_branch" => payload["pull_request"]["head"]["ref"],
      "github_action" => payload["action"],
      "github_pr_url" => payload["pull_request"]["html_url"],
      "github_author" => payload["pull_request"]["user"]["login"]
    }
    error!("No action", 500) unless validated_payload["github_action"].present?
    error!("No branch", 500) unless validated_payload["github_branch"].present?
    error!("No PR URL", 500) unless validated_payload["github_pr_url"].present?
    error!("No author", 500) unless validated_payload["github_author"].present?
    validated_payload
  end


  def self.ignore(payload, pivotal_id)
    api_results(payload, pivotal_id, "ignore")
  end

  def self.nag(payload)
    nag_result = Github.nag_for_a_pivotal_id!(payload["github_pr_url"])
    yagpi_action_taken = nag_result ? "nag" : "nag disabled"
    api_results(payload, nil, yagpi_action_taken)
  end

  def self.handle_missing_pivotal_id(payload)
    return(ignore(payload, nil)) if payload["github_action"] == "closed" 
    nag(payload)
  end

  def self.is_pr_opening?(action)
    %w(opened reopened).include?(action)
  end

  def self.is_pr_closing?(action)
    action == "closed"
  end

  def self.api_results(payload, pivotal_id, yagpi_action_taken)
    {
      "detected_github_action" => payload["github_action"],
      "detected_pivotal_id" => pivotal_id,
      "detected_github_pr_url" => payload["github_pr_url"],
      "detected_github_author" => payload["github_author"],
      "pivotal_action" => yagpi_action_taken
    }
  end

  #TODO: Mirror issues
  def self.receive_hook_and_return_data!(payload)
    return(receive_ping.to_json) if Github.is_github_ping?(payload)
    payload = validate_payload(payload)

    pivotal_id = Pivotal.find_pivotal_id(payload["github_body"], payload["github_branch"])
    handle_missing_pivotal_id(payload) unless pivotal_id.present?

    if is_pr_opening?(payload["github_action"])
      Pivotal.change_story_state!(pivotal_id,
        payload["github_pr_url"], payload["github_author"], 'finished')
      yagpi_action_taken = "finish"
    elsif is_pr_closing?(payload["github_action"])
      Pivotal.change_story_state!(pivotal_id,
        payload["github_pr_url"], payload["github_author"], 'delivered')
      yagpi_action_taken = "deliver"
    else
      return(ignore(payload, pivotal_id))
    end
    api_results(payload, pivotal_id, yagpi_action_taken)
  end
end
