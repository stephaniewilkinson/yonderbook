# frozen_string_literal: true

require 'oauth'

# GoodreadsConnection model for persisting OAuth credentials
class GoodreadsConnection < Sequel::Model
  # How stale last_synced_at may get before we write again. The shelf list is
  # fetched on every visit to /goodreads/shelves; without this the page would
  # cost a database write each time, and "last synced" is not interesting to
  # the minute.
  SYNC_TOUCH_INTERVAL = 3600

  many_to_one :account, key: :user_id

  def validate
    super
    errors.add(:goodreads_user_id, 'is required') if goodreads_user_id.to_s.empty?
    errors.add(:access_token, 'is required') if access_token.to_s.empty?
    errors.add(:access_token_secret, 'is required') if access_token_secret.to_s.empty?
  end

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

  # Records that we successfully reached Goodreads with these credentials.
  # The column existed and the connections page rendered it, but nothing ever
  # wrote it, so the row never appeared.
  def touch_synced
    return if last_synced_at && last_synced_at > Time.now - SYNC_TOUCH_INTERVAL

    update last_synced_at: Time.now
  end

  # Generate an OAuth access token object for making Goodreads API requests
  def oauth_access_token
    consumer = OAuth::Consumer.new(ENV.fetch('GOODREADS_API_KEY'), ENV.fetch('GOODREADS_SECRET'), site: 'https://www.goodreads.com')
    OAuth::AccessToken.new(consumer, access_token, access_token_secret)
  end
end
