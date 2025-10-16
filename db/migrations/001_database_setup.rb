# frozen_string_literal: true

# Migration 001: Database Setup and PRAGMA Configuration
# This migration configures SQLite for production use with proper settings
Sequel.migration do
  up do
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
  end

  down do
    # Reset to SQLite defaults
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
