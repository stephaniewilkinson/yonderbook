# frozen_string_literal: true

# Account model for Rodauth accounts table
class Account < Sequel::Model
  one_to_many :goodreads_connections, key: :user_id

  # Get the primary (most recent) Goodreads connection for this account
  # Always reload from database to avoid stale cached associations
  def goodreads_connection
    goodreads_connections_dataset.order(Sequel.desc(:connected_at)).first
  end

  # Check if user has a connected Goodreads account
  def goodreads_connected?
    # Use exists? for efficiency - just checks if any connection exists
    goodreads_connections_dataset.any?
  end
end
