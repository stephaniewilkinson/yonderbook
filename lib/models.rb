# # frozen_string_literal: true

# require_relative 'db'

# Sequel::Model.plugin :auto_validations
# Sequel::Model.plugin :prepared_statements

# if ENV['RACK_ENV'] == 'development'
#   Sequel::Model.cache_associations = false
#   Unreloader.require('models') { |f| Sequel::Model.send :camelize, File.basename(f).delete_suffix('.rb') }
#   DB.loggers << Logger.new($stdout)
# else
#   Sequel::Model.plugin :subclasses
#   Sequel::Model.freeze_descendents
#   DB.freeze
# end
