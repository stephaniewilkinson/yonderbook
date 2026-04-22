# frozen_string_literal: true

require 'logger'
require 'sequel'

DB = case ENV.fetch('RACK_ENV', 'development')
when 'production'
  Sequel.connect(ENV.fetch('DATABASE_URL'))
when 'test'
  Sequel.connect(ENV.fetch('DATABASE_URL', 'postgres://localhost/yonderbook_test'))
else
  Sequel.connect(ENV.fetch('DATABASE_URL', 'postgres://localhost/yonderbook_dev'))
end

# Enable SQL logging in development only
DB.loggers << Logger.new($stdout) if ENV.fetch('RACK_ENV', 'development') == 'development'
