# frozen_string_literal: true

require 'oauth'

# GoodreadsConnection model for persisting OAuth credentials
class GoodreadsConnection < Sequel::Model
  many_to_one :account, key: :user_id

  def before_create
    super
    self.created_at ||= Time.now
    self.updated_at ||= Time.now
    self.connected_at ||= Time.now
  end

  def before_update
    super
    self.updated_at = Time.now
  end

  # Generate an OAuth access token object for making Goodreads API requests
  def oauth_access_token
    consumer = OAuth::Consumer.new(ENV.fetch('GOODREADS_API_KEY'), ENV.fetch('GOODREADS_SECRET'), site: 'https://www.goodreads.com')
    OAuth::AccessToken.new(consumer, access_token, access_token_secret)
  end
end
