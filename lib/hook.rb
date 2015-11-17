def regex_for_pivotal_id(what)
  what[/[0-9]{7,}/]
end

def find_pivotal_id(body, branch)
  regex_for_pivotal_id(body) || regex_for_pivotal_id(branch)
end

def connect_to_pivotal!
  error!('PIVOTAL_API_KEY not set', 500) unless ENV['PIVOTAL_API_KEY'].present?
  @pivotal_conn ||= RestClient::Resource.new("https://www.pivotaltracker.com/services/v5", :headers => {'X-TrackerToken' => ENV['PIVOTAL_API_KEY'], 'Content-Type' => 'application/json'})
end

def connect_to_github!
  error!('GITHUB_USERNAME not set', 500) unless ENV['GITHUB_USERNAME'].present?
  error!('GITHUB_PASSWORD not set', 500) unless ENV['GITHUB_PASSWORD'].present?
  Octokit.configure do |c|
    c.login = ENV['GITHUB_USERNAME']
    c.password = ENV['GITHUB_PASSWORD']
  end
end

def change_story_state!(pivotal_id, github_pr_url, github_author, pivotal_action)
  connect_to_pivotal!
  pivotal_verb = (pivotal_action == 'finished' ? "Finishes" : "Delivers")
  @pivotal_conn["source_commits"].post('{"source_commit":{"commit_id":"","message":"[' + pivotal_verb + ' #' + pivotal_id + '] ' + pivotal_action.capitalize + ' via YAGPI GitHub Webhook.","url":"' + github_pr_url + '","author":"' + github_author + '"}}')
end

def random_nag
  ["You better post the Pivotal ID or we won't be SOC 2 compliant!",
  "Post the Pivotal ID or SOC 2 will sock you... in the face!",
  "Post the Pivotal ID or you're ruining this company!",
  "You've been in this company how long and don't have a Pivotal ID?",
  "Would you leave your house without your pants? Would you leave a PR without your Pivotal ID?",
  "No Pivotal ID makes SOC 2 mad...",
  "No Pivotal ID in a PR is like not having an umbrella when it rains."].sample
end

def nag_for_a_pivotal_id!(github_pr_url)
  if ENV['POST_TO_GITHUB'] != 1
    connect_to_github!
    urlparts = github_pr_url.split('/')
    Octokit.post("/repos/#{urlparts[3]}/#{urlparts[4]}/issues/#{urlparts[6]}/comments", options = { body: "#{random_nag} Please update the description of the PR with the Pivotal ID, then close and reopen this PR." })
    return true
  end
  false
end

# Github sends a strange param set to ping your app.
# This lets us respond to that ping.
def is_github_ping?(params)
  ZEN = "Responsive is better than fast."
  params["zen"].present? && params["zen"] == ZEN
end

def receive_ping
  { status: "ping_received" }
end

def error!(error_message, error_type)
  halt(error_type,
    {'Content-Type' => 'application/json'}, {
      error: error_type,
      message: error_message
    }.to_json)
end

def receive_hook_and_return_data!(params)
  return(receive_ping) if is_github_ping?(params)

  #TODO: Mirror issues
  github_payload = params["pull_request"]
  error!('No payload', 500) unless github_payload.present?

  #TODO: Clean code
  github_body = github_payload['body']
  github_branch = github_payload['head']['ref']
  github_action = params['action']
  github_pr_url = github_payload['html_url']
  github_author = github_payload['user']['login']
  error!('No action', 500) unless github_action.present?
  error!('No branch', 500) unless github_branch.present?
  error!('No PR URL', 500) unless github_pr_url.present?
  error!('No author', 500) unless github_author.present?

  pivotal_id = find_pivotal_id(github_body, github_branch)
  
  yagpi_action_taken = "none"
  if %w(opened reopened closed).include?(github_action)
    if pivotal_id.present?
      if %w(opened reopened).include?(github_action)
        change_story_state!(pivotal_id, github_pr_url, github_author, 'finished')
        yagpi_action_taken = "finish"
      elsif github_action == "closed"
        change_story_state!(pivotal_id, github_pr_url, github_author, 'delivered')
        yagpi_action_taken = "deliver"
      end
    elsif github_action != "closed" 
      o = nag_for_a_pivotal_id!(github_pr_url)
      yagpi_action_taken = o ? "nag" : "nag disabled"
    end
  end
  
  {
    detected_github_action: github_action,
    detected_pivotal_id: pivotal_id,
    detected_github_pr_url: github_pr_url,
    detected_github_author: github_author,
    pivotal_action: yagpi_action_taken
  }
end
