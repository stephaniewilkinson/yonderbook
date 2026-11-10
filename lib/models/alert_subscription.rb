# frozen_string_literal: true

require 'json'
require 'securerandom'

# A reader's request to be emailed when books on their list come free (#1422).
# One per account; see AvailabilityAlerts for the check itself.
class AlertSubscription < Sequel::Model
  many_to_one :account, key: :user_id

  # Due again after this long. A little under a day, so a daily cron that runs
  # a few minutes early still picks everyone up.
  CHECK_INTERVAL = 20 * 60 * 60

  def self.for_user user_id
    first(user_id: user_id)
  end

  def self.enabled_for? user_id
    where(user_id: user_id, enabled: true).any?
  end

  def self.due now: Time.now
    where(enabled: true).where { (last_checked_at =~ nil) | (last_checked_at < now - CHECK_INTERVAL) }
  end

  def self.new_token = SecureRandom.urlsafe_base64(24)

  # [[consortium_id, library_name], ...]
  def library_list
    parsed = JSON.parse libraries.to_s
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end
end
