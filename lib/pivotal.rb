module Pivotal
  def self.regex_for_pivotal_id(what)
    what[/[0-9]{7,}/]
  end

  def self.find_pivotal_id(body, branch)
    regex_for_pivotal_id(body) || regex_for_pivotal_id(branch)
  end

  def self.connect_to_pivotal!
    error!('PIVOTAL_API_KEY not set', 500) unless ENV['PIVOTAL_API_KEY'].present?
    @pivotal_conn ||= RestClient::Resource.new("https://www.pivotaltracker.com/services/v5", :headers => {'X-TrackerToken' => ENV['PIVOTAL_API_KEY'], 'Content-Type' => 'application/json'})
  end

  def self.change_story_state!(pivotal_id, github_pr_url, github_author, pivotal_action)
    connect_to_pivotal!
    pivotal_verb = (pivotal_action == 'finished' ? "Finishes" : "Delivers")
    @pivotal_conn["source_commits"].post('{"source_commit":{"commit_id":"","message":"[' + pivotal_verb + ' #' + pivotal_id + '] ' + pivotal_action.capitalize + ' via YAGPI GitHub Webhook.","url":"' + github_pr_url + '","author":"' + github_author + '"}}')
  end
end
