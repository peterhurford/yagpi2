class Pivotal
  def self.regex_for_pivotal_id(what)
    what[/[0-9]{7,}/]
  end

  def self.find_pivotal_id(body, branch)
    regex_for_pivotal_id(body) || regex_for_pivotal_id(branch)
  end

  def self.connect_to_pivotal!
    error!('PIVOTAL_API_KEY not set', 500) unless ENV['PIVOTAL_API_KEY'].present?
    @pivotal_conn ||= RestClient::Resource.new("https://www.pivotaltracker.com/services/v5",
       :headers => {'X-TrackerToken' => ENV['PIVOTAL_API_KEY'], 'Content-Type' => 'application/json'})
  end

  def self.pivotal_verb(pivotal_action)
    pivotal_action == 'finished' ? "Finishes" : "Delivers"
  end

  def self.pivotal_yagpi_comment(pivotal_id, pivotal_action)
    "[" + pivotal_verb(pivotal_action) + " #" + pivotal_id + "] " +
      pivotal_action.capitalize + " via YAGPI GitHub Webhook."
  end

  def self.pivotal_post_message(pivotal_id, github_pr_url, github_author, pivotal_action)
    '{"source_commit":{"commit_id":"","message":"' +
      pivotal_yagpi_comment(pivotal_id, pivotal_action) +
      ',"url":"' + github_pr_url +
      ',author:":"' + github_author + '"}}'
  end

  def self.change_story_state!(pivotal_id, github_pr_url, github_author, pivotal_action)
    connect_to_pivotal!
    @pivotal_conn["source_commits"].post(
      pivotal_post_message(pivotal_id, github_pr_url, github_author, pivotal_action))
  end
end
