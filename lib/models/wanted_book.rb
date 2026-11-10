# frozen_string_literal: true

# A book on a reader's list that none of their libraries had when they turned
# alerts on, searched for again weekly (#1422). See AvailabilityAlerts.
class WantedBook < Sequel::Model
  many_to_one :account, key: :user_id

  # The shape Overdrive's title search takes.
  def to_book = {title: title, author: author, isbn: isbn}
end
