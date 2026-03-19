# frozen_string_literal: true

# Add tables for Rodauth email_auth and active_sessions features
Sequel.migration do
  change do
    create_table :account_email_auth_keys do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table :account_active_session_keys do
      foreign_key :account_id, :accounts, type: :Bignum
      String :session_id
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
      primary_key %i[account_id session_id]
    end
  end
end
