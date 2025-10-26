# frozen_string_literal: true

# Initial Schema Migration
# Sets up the entire database schema for Yonderbook including SQLite configuration,
# accounts table, and Rodauth authentication tables
Sequel.migration do
  up do
    # SQLite PRAGMA Configuration for production use
    # Enable Write-Ahead Logging (WAL) mode for better concurrency
    # WAL mode allows readers and writers to operate simultaneously
    run 'PRAGMA journal_mode = WAL'

    # Enable foreign key constraint checking
    # SQLite has FK support but it's disabled by default
    run 'PRAGMA foreign_keys = ON'

    # Set synchronous mode to NORMAL for better performance while maintaining safety
    # FULL = safest but slowest, NORMAL = good balance, OFF = fastest but risky
    run 'PRAGMA synchronous = NORMAL'

    # Set busy timeout to 5 seconds (5000ms)
    # This prevents immediate "database is locked" errors
    run 'PRAGMA busy_timeout = 5000'

    # Enable automatic index creation for foreign keys
    run 'PRAGMA automatic_index = ON'

    # Set temp storage to memory for better performance
    run 'PRAGMA temp_store = MEMORY'

    # Set cache size to 10MB (negative value = KB, positive = pages)
    # -10000 = 10MB of cache
    run 'PRAGMA cache_size = -10000'

    # Enable memory-mapped I/O for better read performance (256MB limit)
    run 'PRAGMA mmap_size = 268435456'

    # Main accounts table
    create_table :accounts do
      primary_key :id
      String :email, null: false
      index :email, unique: true
      String :password_hash
      String :first_name
      String :last_name
      Integer :status_id, null: false, default: 1
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Account verification keys for email verification
    # Used by Rodauth verify_account feature
    create_table :account_verification_keys do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Password reset keys
    # Used by Rodauth reset_password feature
    create_table :account_password_reset_keys do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Login failures tracking
    # Used by Rodauth lockout feature (if enabled)
    create_table :account_login_failures do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      Integer :number, null: false, default: 1
    end
  end

  down do
    drop_table :account_login_failures
    drop_table :account_password_reset_keys
    drop_table :account_verification_keys
    drop_table :accounts

    # Reset SQLite to defaults
    run 'PRAGMA journal_mode = DELETE'
    run 'PRAGMA foreign_keys = OFF'
    run 'PRAGMA synchronous = FULL'
    run 'PRAGMA busy_timeout = 0'
    run 'PRAGMA automatic_index = ON'
    run 'PRAGMA temp_store = DEFAULT'
    run 'PRAGMA cache_size = -2000'
    run 'PRAGMA mmap_size = 0'
  end
end
