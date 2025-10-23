require "mechanize"
require "json"
require "scraperwiki"

agent = Mechanize.new
agent.user_agent = "Ruby/#{RUBY_VERSION} PlanningAlerts scraper for SA Planning Portal (https://www.planningalerts.org.au/about)"
agent.request_headers = {
  "Accept" => "application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language" => "en-AU,en-GB;q=0.8,en-US;q=0.5,en;q=0.3",
  "Accept-Encoding" => "gzip, deflate",
  "Connection" => "keep-alive",
}

# This endpoint is not "protected" by Kasada
url = "https://plan.sa.gov.au/have_your_say/notified_developments/current_notified_developments/assets/getpublicnoticessummary"
applications = JSON.parse(agent.post(url).body)
puts "Found #{applications.length} applications to process"
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

  # Instead of sending all comments to PlanSA we want to send comments to the individual councils
  # Luckily that information (the email address) is available by call the "detail" endpoint
  sleep(rand(1.0...3.0))
  page = agent.post("https://plan.sa.gov.au/have_your_say/notified_developments/current_notified_developments/assets/getpublicnoticedetail", aid: application["applicationID"])
  detail = JSON.parse(page.body)
  record["comment_email"] = detail["email"]
  record["comment_authority"] = detail["organisation"]

  puts "Saving record #{record['council_reference']}, #{record['address']}"
  ScraperWiki.save_sqlite(['council_reference'], record)
end
