# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'sequel'

# Database configuration
DB = case ENV.fetch('RACK_ENV', 'development')
when 'production'
  # Production: Use SQLite database file
  Sequel.sqlite('db/production.db')
when 'test'
  # Test: Use in-memory SQLite for fast tests
  Sequel.sqlite
else
  # Development: Use SQLite database file
  Sequel.sqlite('db/development.db')
end

# Enable SQL logging in all environments
# Logs to stdout which Render captures in deployment logs
DB.loggers << Logger.new($stdout)

# Create database directory if it doesn't exist
FileUtils.mkdir_p('db')
