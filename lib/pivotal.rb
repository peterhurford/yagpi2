require "rest-client"

class Pivotal
  def self.regex_for_pivotal_id(what)
    return false if what.nil?
    what[/[0-9]{7,}/]
  end

  def self.find_pivotal_id(body, branch)
    regex_for_pivotal_id(body) || regex_for_pivotal_id(branch)
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


  def self.bug_template(github_title, github_url)
    { story_type: "bug", labels: ["bugs", "triage"], name: github_title,
      description: github_url }.to_json
  end

  def self.projects_url
    "projects/#{ENV['PIVOTAL_PROJECT_ID']}/stories"
  end

  def self.create_a_bug!(github_title, github_url)
    connect_to_pivotal!
    story = pivotal_conn[projects_url].post(
      bug_template(github_title, github_url))
    JSON.parse(story)["url"]     # Return the Pivotal URL for cross-posting on the issue.
  end


  def self.pivotal_verb(pivotal_action)
    pivotal_action == 'finished' ? "Finishes" : "Delivers"
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

  def self.get_story(pivotal_id)
    JSON.parse(pivotal_conn["stories/#{pivotal_id}"].get())
  end

  def self.get_story_labels(pivotal_id)
    get_story(pivotal_id)["labels"].map { |h| h["name"] }
  end

  def self.assign!(pivotal_id, assignee)
    # Pivotal doesn't let you assign stories by API :(
    # And GitHub handles are different from Pivotal handles anyway,
    # so we'll assign by label and clean it up in post.
    label_!(pivotal_id,
      get_story_labels(pivotal_id).reject { |v| v =~ /assign/ } +
        ["assignee:#{assignee}", "bugs"])
    comment!(pivotal_id, "Assigned to #{assignee}.")
  end

  def self.label_!(pivotal_id, labels)
    pivotal_conn["#{projects_url}/#{pivotal_id}"].put({ labels: labels }.to_json)
  end

  def self.label!(pivotal_id, labels)
    # Avoid overwritting assignee label
    labels = get_story_labels(pivotal_id).select { |v| v =~ /assign/ } + ["bugs"] + labels
    label_!(pivotal_id, labels)
    comment!(pivotal_id, "Labels changed to #{(labels.join(', ') rescue nil)}.")
  end
end
