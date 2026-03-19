# frozen_string_literal: true

require 'oauth'

module Auth
  API_KEY = ENV.fetch('GOODREADS_API_KEY')
  GOODREADS_SECRET = ENV.fetch('GOODREADS_SECRET')
  SITE = 'https://www.goodreads.com'

  module_function

  def new_consumer
    OAuth::Consumer.new(API_KEY, GOODREADS_SECRET, site: SITE)
  end

  def fetch_request_token
    new_consumer.get_request_token
  end

  def rebuild_access_token access_token, access_token_secret
    OAuth::AccessToken.new(new_consumer, access_token, access_token_secret)
  end
end
