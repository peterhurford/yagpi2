require "octokit"

class Github
  def self.client
    @client = begin
      Api.error!('GITHUB_PAT not set', 500) unless ENV['GITHUB_PAT'].present?
      Octokit::Client.new(:access_token => ENV["GITHUB_PAT"])
    end
  end

  def self.random_nag
    [
      "You better post the Pivotal ID or we won't be SOC 2 compliant!",
      "Post the Pivotal ID or SOC 2 will sock you... in the face!",
      "Post the Pivotal ID or you're ruining this company!",
      "You've been in this company how long and don't have a Pivotal ID?",
      "Would you leave your house without your pants? Would you leave a PR without your Pivotal ID?",
      "No Pivotal ID makes SOC 2 mad...",
      "No Pivotal ID in a PR is like not having an umbrella when it rains."
    ].sample
  end

  def self.nag_message
    "#{random_nag} Please update the description of the PR with the Pivotal ID, then close and reopen this PR."
  end

  # Converts an absolute GitHub URL into the relative comments url for the PR
  def self.get_relative_comments_url(github_url)
    urlparts = github_url.split('/')
    "/repos/#{urlparts[3]}/#{urlparts[4]}/issues/#{urlparts[6]}/comments"
  end

  def self.get_issue_number_from_url(github_url)
    github_url.split("/")[-1]
  end

  def self.get_repo_from_url(github_url)
    github_url.split("/")[3, 2].join("/")
  end

  def self.post_to_github!(github_url, message)
    if ENV['DONT_POST_TO_GITHUB'] != 1
      client.post(get_relative_comments_url(github_url),
        options = { body: message })
      true
    else
      false
    end
  end

  def self.nag_for_a_pivotal_id!(github_url)
    post_to_github!(github_url, nag_message)
  end

  def self.post_pivotal_link_on_issue!(github_url, github_title, github_body, pivotal_url)
    repo = get_repo_from_url(github_url)
    issue_number = get_issue_number_from_url(github_url)
    pivotal_id_message = "PIVOTAL: #{pivotal_url}"
    new_issue_body = github_body + "\n\n" + pivotal_id_message
    client.update_issue(repo, issue_number, github_title, new_issue_body)
    post_to_github!(github_url, pivotal_id_message)
  end

  # Github sends a strange param set to ping your app.
  # This lets us respond to that ping.
  def self.is_github_ping?(payload)
    payload["zen"].present?
  end

  def self.is_pull_request_action?(payload)
    payload["pull_request"].present?
  end

  def self.is_issue_action?(payload)
    payload["issue"].present?
  end
end
