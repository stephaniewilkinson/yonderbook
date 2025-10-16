# frozen_string_literal: true

Sequel.migration do
  up do
    # Main accounts table
    create_table :accounts do
      primary_key :id
      String :email, null: false
      index :email, unique: true
      String :password_hash
      Integer :status_id, null: false, default: 1
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Password reset
    create_table :account_password_reset_keys do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Login failures tracking
    create_table :account_login_failures do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      Integer :number, null: false, default: 1
    end
  end

  down do
    drop_table :account_login_failures
    drop_table :account_password_reset_keys
    drop_table :accounts
  end
end
