# frozen_string_literal: true

require_relative '../.env'
require 'sequel'

# Delete DATABASE_URL from the environment, so it isn't accidently
# passed to subprocesses.  DATABASE_URL may contain passwords.
# DB = Sequel.connect ENV.delete 'DATABASE_URL'
