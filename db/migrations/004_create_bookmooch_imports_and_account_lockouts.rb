# frozen_string_literal: true

# Track books sent to BookMooch and add Rodauth lockout support
Sequel.migration do
  change do
    create_table :bookmooch_imports do
      primary_key :id
      foreign_key :user_id, :accounts, null: false, on_delete: :cascade
      String :isbn, null: false
      String :bookmooch_isbn
      String :shelf_name
      DateTime :last_seen_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index %i[user_id isbn], unique: true, name: :bookmooch_imports_unique
      index :user_id, name: :bookmooch_imports_user_id
    end

    create_table :account_lockouts do
      foreign_key :id, :accounts, primary_key: true
      String :key, null: false
      DateTime :deadline
      DateTime :email_last_sent
    end
  end
end
