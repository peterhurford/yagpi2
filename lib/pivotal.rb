require "rest-client"

class Pivotal
  def self.regex_for_pivotal_id_in_branch(what)
    return nil if what.nil?
    what[/[0-9]{7,}/]
  end

  def self.regex_for_pivotal_id_in_body(what)
    return nil if what.nil?
    captures = what[/#[0-9]{7,}/] || what[/show\/[0-9]{7,}/] || what[/stories\/[0-9]{7,}/]
    captures[/[0-9]{7,}/] if captures
  end

  def self.find_pivotal_id(body, branch)
    regex_for_pivotal_id_in_body(body) || regex_for_pivotal_id_in_branch(branch)
  end


  def self.pivotal_conn
    pivotal_conn ||= begin
      Api.error!("PIVOTAL_API_KEY not set", 500) unless ENV["PIVOTAL_API_KEY"].present?
      Api.error!("PIVOTAL_PROJECT_ID not set", 500) unless ENV["PIVOTAL_PROJECT_ID"].present?
      RestClient::Resource.new("https://www.pivotaltracker.com/services/v5",
       :headers => {"X-TrackerToken" => ENV["PIVOTAL_API_KEY"],
                    "Content-Type" => "application/json"})
    end
  end


  def self.story_template(github_title, github_url, story_type = "feature", labels = [])
    { story_type: story_type, labels: labels, name: github_title, description: github_url }.to_json
  end

  def self.projects_url
    "projects/#{ENV['PIVOTAL_PROJECT_ID']}/stories"
  end


  def self.create_a_story!(github_title, github_url, labels, assignee, story_type)
    if story_type == "bug"
      story = story_template(github_title, github_url,
        story_type = "bug", labels = ["bugs", "triage"])
    else
      story = story_template(github_title, github_url)
    end
    story = pivotal_conn[projects_url].post(story)
    pivotal_url = JSON.parse(story)["url"]
    pivotal_id = regex_for_pivotal_id_in_body(pivotal_url)
    assign!(pivotal_id, assignee) unless assignee.nil?
    label!(pivotal_id, labels) unless labels.empty?
    pivotal_url  # Return the Pivotal URL for cross-posting on the issue.
  end


  def self.pivotal_verb(pivotal_action)
    if pivotal_action == "delivered"
      "Delivers"
    else
      "Finishes"
    end
  end

  def self.pivotal_yagpi_comment(pivotal_id, pivotal_action)
    return nil if pivotal_id.nil? || pivotal_action.nil?
    "[" + pivotal_verb(pivotal_action) + " #" + pivotal_id + "] " +
      pivotal_action.capitalize + " via YAGPI GitHub Webhook."
  end

  def self.source_commit!(comment, github_url, github_author)
    pivotal_conn["source_commits"].post({
      source_commit: {
        commit_id: "",
        message: comment,
        url: github_url,
        author: github_author
      }
    }.to_json)
  end


  def self.comment!(pivotal_id, comment)
    pivotal_conn["#{projects_url}/#{pivotal_id}/comments"].post({
      text: comment
    }.to_json)
  end

  def self.change_story_state!(pivotal_id, github_url, github_author, pivotal_action)
    source_commit!(pivotal_yagpi_comment(pivotal_id, pivotal_action), github_url, github_author)
  end


  def self.finish!(pivotal_id, github_url, github_author)
    change_story_state!(pivotal_id, github_url, github_author, "finished")
  end

  def self.deliver!(pivotal_id, github_url, github_author)
    change_story_state!(pivotal_id, github_url, github_author, "delivered")
  end

  def self.accept!(pivotal_id)
    pivotal_conn["#{projects_url}/#{pivotal_id}"].put({ current_state: "accepted" }.to_json)
  end

  def self.deliver_and_accept!(pivotal_id, github_url, github_author)
    deliver!(pivotal_id, github_url, github_author)
    accept!(pivotal_id)
  end

  def self.get_story(pivotal_id)
    JSON.parse(pivotal_conn["stories/#{pivotal_id}"].get())
  end

  def self.get_story_labels(pivotal_id)
    get_story(pivotal_id)["labels"].map { |h| h["name"] }
  end

  def self.assign!(pivotal_id, assignee)
    begin
      labels = get_story_labels(pivotal_id)
   rescue
     return nil   # Avoid crashing if we try to label a story that doesn't exist yet.
   end
    # Pivotal doesn't let you assign stories by API :(
    # And GitHub handles are different from Pivotal handles anyway,
    # so we'll assign by label and clean it up in post.
    label_!(pivotal_id,
      # Keep all labels except the assignee label; replace the assignee label.
      labels.reject { |v| v =~ /assign/ } + ["assignee:#{assignee}"])
    comment!(pivotal_id, "Assigned to #{assignee}.")
  end

  def self.turn_to_bug!(pivotal_id)
    change_story_type!(pivotal_id, "bug")
  end

  def self.turn_to_feature!(pivotal_id)
    change_story_type!(pivotal_id, "feature")
  end

  def self.change_story_type!(pivotal_id, story_type)
    pivotal_conn["#{projects_url}/#{pivotal_id}"].put({ story_type: story_type }.to_json)
  end

  def self.is_bug_by_type(pivotal_id)
    get_story(pivotal_id)["story_type"] == "bug"
  end

  def self.is_bug_by_labels(labels)
    # It must have one bug label other than the bugs epic label.
    (labels - ["bugs"]).grep(/bug/)
  end

  def self.label_!(pivotal_id, labels)
    pivotal_conn["#{projects_url}/#{pivotal_id}"].put({ labels: labels }.to_json)
  end

  def self.label!(pivotal_id, labels)
    begin
      labels = get_story_labels(pivotal_id)
   rescue
     return nil   # Avoid crashing if we try to label a story that doesn't exist yet.
   end
    # Avoid overwritting assignee and bugs labels
    labels = labels.select { |v| v =~ /assign/ } + labels
    
    if is_bug_by_labels(labels) && !is_bug_by_type(pivotal_id)
      turn_to_bug!(pivotal_id)
      labels = ["bugs"] + labels
    end
    if !is_bug_by_labels(labels) && is_bug_by_type(pivotal_id)
      turn_to_feature!(pivotal_id)
    end

    label_!(pivotal_id, labels)
    comment!(pivotal_id, "Labels changed to #{(labels.join(', ') rescue nil)}.")
  end
end
