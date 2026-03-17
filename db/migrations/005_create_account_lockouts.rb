# frozen_string_literal: true

# Required tables for Rodauth lockout feature (rate limiting failed logins)
Sequel.migration do
  change do
    create_table :account_lockouts do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :deadline
      DateTime :email_last_sent
    end
  end
end
