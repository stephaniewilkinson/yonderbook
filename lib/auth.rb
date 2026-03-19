# frozen_string_literal: true

require 'oauth'

module Auth
  API_KEY = ENV.fetch('GOODREADS_API_KEY')
  GOODREADS_SECRET = ENV.fetch('GOODREADS_SECRET')
  HOST = 'www.goodreads.com'
  OAUTH_CONSUMER = OAuth::Consumer.new API_KEY, GOODREADS_SECRET, site: "https://#{HOST}"

  module_function

  def fetch_request_token
    OAUTH_CONSUMER.get_request_token
  rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::HTTPFatalError, Errno::EBADF
    # Errno::EBADF happens when Falcon forks workers and the parent's SSL
    # connection becomes invalid. Create a fresh consumer to get a clean socket.
    tries ||= 0
    tries += 1
    consumer = OAuth::Consumer.new(API_KEY, GOODREADS_SECRET, site: "https://#{HOST}")
    retry if tries < 4
  end

  def rebuild_access_token access_token, access_token_secret
    OAuth::AccessToken.new(OAUTH_CONSUMER, access_token, access_token_secret)
  end
end
