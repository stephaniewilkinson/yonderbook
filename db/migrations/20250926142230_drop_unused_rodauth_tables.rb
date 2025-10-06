# frozen_string_literal: true

Sequel.migration do
  up do
    # Drop tables for removed Rodauth features
    drop_table :account_verification_keys if table_exists?(:account_verification_keys)
    drop_table :account_remember_keys if table_exists?(:account_remember_keys)
  end

  down do
    # Recreate tables if migration is rolled back
    create_table :account_verification_keys do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table :account_remember_keys do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
    end
  end
end
