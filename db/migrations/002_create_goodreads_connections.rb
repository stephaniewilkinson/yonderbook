# frozen_string_literal: true

# Create goodreads_connections table for managing Goodreads OAuth connections
Sequel.migration do
  change do
    create_table(:goodreads_connections) do
      primary_key :id
      foreign_key :user_id, :accounts, null: false, on_delete: :cascade
      String :goodreads_user_id, null: false # User's Goodreads ID
      String :access_token, null: false # OAuth 1.0a access token
      String :access_token_secret, null: false # OAuth 1.0a secret
      DateTime :connected_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_synced_at # Last time we synced shelves from Goodreads
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      # Prevent duplicate connections to the same Goodreads account
      index %i[user_id goodreads_user_id], unique: true, name: :goodreads_connections_unique
      # Index for looking up all connections for a user
      index :user_id, name: :goodreads_connections_user_id
      # Index for looking up by Goodreads user ID
      index :goodreads_user_id, name: :goodreads_connections_goodreads_user_id
    end
  end
end
