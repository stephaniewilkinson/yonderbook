# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'sequel'

# Database configuration with SQLite optimizations
DB = case ENV.fetch('RACK_ENV', 'development')
when 'production'
  # Production: Use persistent disk at /var/data (Render mount point)
  # Ensure directory exists
  FileUtils.mkdir_p('/var/data')

  Sequel.sqlite(
    '/var/data/production.db',
    # Enable foreign key constraints
    foreign_keys: true,
    # Set synchronous mode to NORMAL (good balance of safety/performance)
    synchronous: :normal,
    # Use memory for temp storage
    temp_store: :memory,
    # Set busy timeout to 5 seconds
    timeout: 5000
  )
when 'test'
  # Test: Use in-memory SQLite for fast tests
  Sequel.sqlite(foreign_keys: true, synchronous: :normal, temp_store: :memory)
else
  # Development: Use SQLite database file in db/ directory
  FileUtils.mkdir_p('db')

  Sequel.sqlite('db/development.db', foreign_keys: true, synchronous: :normal, temp_store: :memory, timeout: 5000)
end

# Enable SQL logging in development only
DB.loggers << Logger.new($stdout) if ENV.fetch('RACK_ENV', 'development') == 'development'
