class Api
  @@raises = false

  def self.receive_ping
    { "status" => "ping_received" }
  end

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
      github_body: payload["body"],
      github_branch: payload["head"]["ref"],
      github_action: payload["action"],
      github_pr_url: payload["html_url"],
      github_author: payload["user"]["login"]
    }
    error!("No action", 500) unless validated_payload[:github_action].present?
    error!("No branch", 500) unless validated_payload[:github_branch].present?
    error!("No PR URL", 500) unless validated_payload[:github_pr_url].present?
    error!("No author", 500) unless validated_payload[:github_author].present?
    validated_payload
  end

  def self.receive_hook_and_return_data!(params)
    return(receive_ping.to_json) if Github.is_github_ping?(params)

    #TODO: Mirror issues
    payload = params["pull_request"]
    error!('No payload', 500) unless payload.present?

    payload = validate_payload(payload)

    pivotal_id = Pivotal.find_pivotal_id(payload["github_body"], payload["github_branch"])
    
    yagpi_action_taken = "none"
    if %w(opened reopened closed).include?(payload["github_action"])
      if pivotal_id.present?
        if %w(opened reopened).include?(payload["github_action"])
          change_story_state!(pivotal_id, payload["github_pr_url"], github_author, 'finished')
          yagpi_action_taken = "finish"
        elsif payload["github_action"] == "closed"
          change_story_state!(pivotal_id, payload["github_pr_url"], github_author, 'delivered')
          yagpi_action_taken = "deliver"
        end
      elsif payload["github_action"] != "closed" 
        o = nag_for_a_pivotal_id!(payload["github_pr_url"])
        yagpi_action_taken = o ? "nag" : "nag disabled"
      end
    end
    
    {
      detected_github_action: payload["github_action"],
      detected_pivotal_id: pivotal_id,
      detected_github_pr_url: payload["github_pr_url"],
      detected_github_author: github_author,
      pivotal_action: yagpi_action_taken
    }
  end
end
