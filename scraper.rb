require "mechanize"
require "json"
require "scraperwiki"

# Require a delay between requests to avoid 429 => Net::HTTPTooManyRequests errors
# 10 to 20 worked, but added 5 seconds to be safer
DELAY_BETWEEN_REQUESTS_RANGE = 15.0...25.0

agent = Mechanize.new
agent.user_agent = "Ruby/#{RUBY_VERSION} PlanningAlerts scraper for SA Planning Portal (https://www.planningalerts.org.au/about)"
agent.request_headers = {
  "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language" => "en-AU,en-GB;q=0.8,en-US;q=0.5,en;q=0.3",
  "Accept-Encoding" => "gzip, deflate",
  "Connection" => "keep-alive",
}
# cookie_file = Tempfile.new(['sa_planning_cookies', '.txt'])
# agent.cookie_jar.save_as = cookie_file.path
agent.follow_meta_refresh = true
agent.redirect_ok = true

proxy = ENV["MORPH_AUSTRALIAN_PROXY"]
if proxy
  # On morph.io set the environment variable MORPH_AUSTRALIAN_PROXY to
  # http://morph:password@au.proxy.oaf.org.au:8888 replacing password with
  # the real password.
  puts "Using Australian proxy..."
  agent.agent.set_proxy(proxy)
end

url = "https://plan.sa.gov.au/have_your_say/notified_developments/current_notified_developments"
puts "Visiting html page to set cookies: #{url} ..."
agent.get(url)

# This endpoint is not "protected" by Kasada, but probably is by Cloudflare
# url = "https://plan.sa.gov.au/have_your_say/notified_developments/current_notified_developments/assets/getpublicnoticessummary"
url = "https://cdn.plan.sa.gov.au/public-notifications/getpublicnoticessummary"
response = agent.post(url)
puts "Got #{response.code} response from #{url} with headers: #{response.header.inspect}"
applications = JSON.parse(response.body)
puts "Found #{applications.length} applications to process"

found_again = new_records = 0
applications.each do |application|
  record = {
    "council_reference" => application["applicationID"].to_s,
    # If there are multiple addresses they are all included in this field separated by ","
    # Only use the first address
    "address" => application["propertyAddress"].split(",").first,
    "description" => application["developmentDescription"],
    # Not clear whether this page will stay around after the notification period is over
    "info_url" => "https://plan.sa.gov.au/have_your_say/notified_developments/current_notified_developments/submission?aid=#{application['publicNotificationID']}",
    "date_scraped" => Date.today.to_s,
    "on_notice_to" => Date.strptime(application["closingDate"], "%m/%d/%Y").to_s
  }

  existing = ScraperWiki.select("* from data where council_reference = ?", record["council_reference"])
  if existing&.length == 1
    record["comment_email"] = existing.first["comment_email"]
    record["comment_authority"] = existing.first["comment_authority"]
  end

  if record["comment_authority"].present? && record["comment_email"].present?
    puts "Reusing comment email and authority from existing record: #{record['council_reference']}"
    found_again += 1
  else
    puts "Retrieving comment email and authority from detail page: #{record['council_reference']}"
    new_records += 1
    sleep(rand(DELAY_BETWEEN_REQUESTS_RANGE))
    # Send comments to the individual councils from the details endpoint rather than PlanSA
    page = agent.post("https://plan.sa.gov.au/have_your_say/notified_developments/current_notified_developments/assets/getpublicnoticedetail", aid: application["applicationID"])
    detail = JSON.parse(page.body)
    record["comment_email"] = detail["email"]
    record["comment_authority"] = detail["organisation"]
  end

  puts "Saving record #{record['council_reference']}, #{record['address']}"
  ScraperWiki.save_sqlite(['council_reference'], record)
end
puts "Found #{found_again} applications that were already in the database, and added #{new_records} new applications."
