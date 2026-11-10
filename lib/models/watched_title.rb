# frozen_string_literal: true

# One copy a reader is watching: a format of a book at one library, keyed by
# OverDrive's product id there (#1422).
class WatchedTitle < Sequel::Model
  many_to_one :account, key: :user_id
end
