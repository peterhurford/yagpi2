require "./lib/github"
require "./lib/pivotal"

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


  def self.validate_payload(payload, type)
    error!("Malformed payload", 500) unless payload[type].is_a?(Hash)
    validated_payload = {
      "type" => type,
      "title" => payload[type]["title"],
      "body" => payload[type]["body"],
      "action" => payload["action"],
      "url" => payload[type]["html_url"],
      "author" => payload[type]["user"]["login"],
      "labels" => (payload[type]["labels"].map(&:values) rescue nil),
      "assignee" => payload[type]["assignee"]
    }
    error!("No action", 500) unless validated_payload["action"].present?
    error!("No URL", 500) unless validated_payload["url"].present?
    error!("No author", 500) unless validated_payload["author"].present?
    validated_payload
  end

  def self.validate_pull_request_payload(payload)
    validated_payload = validate_payload(payload, "pull_request")
    validated_payload["branch"] = payload["pull_request"]["head"]["ref"]
    validated_payload["merged"] = payload["pull_request"]["merged"]
    error!("No branch", 500) unless validated_payload["branch"].present?
    validated_payload
  end

  def self.validate_issue_payload(payload)
    validate_payload(payload, "issue")
  end


  def self.ignore(payload, pivotal_id)
    api_results(payload, pivotal_id, "ignore")
  end

  def self.nag(payload)
    nag_result = Github.nag_for_a_pivotal_id!(payload["url"])
    yagpi_action_taken = nag_result ? "nag" : "nag disabled"
    api_results(payload, nil, yagpi_action_taken)
  end

  def self.is_opening?(action)
    %w(opened reopened).include?(action)
  end

  def self.is_closing?(action)
    action == "closed"
  end

  def self.is_merging?(merge_action)
    merge_action == true
  end

  def self.is_assigning?(action)
    %w(assigned unassigned).include?(action)
  end

  def self.is_labeling?(action)
    %w(labeled unlabeled).include?(action)
  end

  def self.api_results(payload, pivotal_id, yagpi_action_taken)
    payload.tap do |p|
      p["labels"] = (p["labels"].join(", ") rescue nil)
      p["pivotal_id"] = pivotal_id
      p["pivotal_action"] = yagpi_action_taken
    end
  end


  def self.receive_hook_and_return_data!(payload)
    if Github.is_github_ping?(payload)
      receive_ping
    elsif Github.is_pull_request_action?(payload)
      handle_pull_request_action(payload)
    elsif Github.is_issue_action?(payload)
      handle_issue_action(payload)
    else
      error!("Received a payload that was not a pull request or an issue.", 500)
    end
  end


  def self.handle_pull_request_action(payload)
    payload = validate_pull_request_payload(payload)
    pivotal_id = Pivotal.find_pivotal_id(payload["body"], payload["branch"])

    if is_opening?(payload["action"])
      yagpi_action_taken = ""
      unless pivotal_id.present?
        nag(payload) 
        yagpi_action_taken += "nag"
      end
      Pivotal.finish!(pivotal_id, payload["url"], payload["author"])
      yagpi_action_taken += "finish"
    elsif is_closing?(payload["action"])
      if is_merging?(payload["merged"])
        Pivotal.deliver!(pivotal_id, payload["url"], payload["author"])
        yagpi_action_taken = "deliver"
      else
        yagpi_action_taken = "ignore"
      end
    else
      return(ignore(payload, pivotal_id))
    end
    api_results(payload, pivotal_id, yagpi_action_taken)
  end


  def self.handle_issue_action(payload)
    payload = validate_issue_payload(payload)
    pivotal_id = Pivotal.find_pivotal_id(payload["body"], nil)

    if is_opening?(payload["action"])
      piv_url = Pivotal.create_a_bug!(payload["title"], payload["url"])
      Github.post_pivotal_link_on_issue!(payload, piv_url)
      yagpi_action_taken = "create"
    elsif is_assigning?(payload["action"])
      # ...
      yagpi_action_taken = "assign"
    elsif is_labeling?(payload["action"])
      # ...
      yagpi_action_taken = "label"
    else
      return(ignore(payload, pivotal_id))
    end
    api_results(payload, pivotal_id, yagpi_action_taken)
  end
end
