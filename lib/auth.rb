# frozen_string_literal: true

require 'oauth'

module Auth
  API_KEY = ENV.fetch 'GOODREADS_API_KEY'
  GOODREADS_SECRET = ENV.fetch 'GOODREADS_SECRET'
  HOST = 'www.goodreads.com'
  OAUTH_CONSUMER = OAuth::Consumer.new API_KEY, GOODREADS_SECRET, site: "https://#{HOST}"

  module_function

  def fetch_request_token
    OAUTH_CONSUMER.get_request_token
  rescue Net::HTTPBadResponse, Net::OpenTimeout
    # Starting with the simplest fix. If this doesn't work, the next idea
    # is to create a new consumer here and retry.
    tries ||= 0
    tries += 1
    retry if tries < 4
  end

  def rebuild_access_token user
    OAuth::AccessToken.new(OAUTH_CONSUMER, user[:access_token], user[:access_token_secret])
  end
end
