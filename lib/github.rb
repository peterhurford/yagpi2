class Github
  def self.connect_to_github!
    error!('GITHUB_USERNAME not set', 500) unless ENV['GITHUB_USERNAME'].present?
    error!('GITHUB_PASSWORD not set', 500) unless ENV['GITHUB_PASSWORD'].present?
    Octokit.configure do |c|
      c.login = ENV['GITHUB_USERNAME']
      c.password = ENV['GITHUB_PASSWORD']
    end
  end

  def self.random_nag
    ["You better post the Pivotal ID or we won't be SOC 2 compliant!",
    "Post the Pivotal ID or SOC 2 will sock you... in the face!",
    "Post the Pivotal ID or you're ruining this company!",
    "You've been in this company how long and don't have a Pivotal ID?",
    "Would you leave your house without your pants? Would you leave a PR without your Pivotal ID?",
    "No Pivotal ID makes SOC 2 mad...",
    "No Pivotal ID in a PR is like not having an umbrella when it rains."].sample
  end

  def self.nag_message
    "#{random_nag} Please update the description of the PR with the Pivotal ID, then close and reopen this PR."
  end

  def self.parse_github_url(github_pr_url)
    urlparts = github_pr_url.split('/')
    "/repos/#{urlparts[3]}/#{urlparts[4]}/issues/#{urlparts[6]}/comments"
  end

  def self.nag_for_a_pivotal_id!(github_pr_url)
    if ENV['POST_TO_GITHUB'] != 1
      connect_to_github!
      Octokit.post(parse_github_url(github_pr_url),
        options = { body: nag_message })
      true
    else
      false
    end
  end

  # Github sends a strange param set to ping your app.
  # This lets us respond to that ping.
  def self.is_github_ping?(params)
    zen = "Responsive is better than fast."
    params["zen"].present? && params["zen"] == zen
  end
end
