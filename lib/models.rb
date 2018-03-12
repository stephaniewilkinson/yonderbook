# frozen_string_literal: true

require_relative 'db'

Sequel::Model.plugin :auto_validations
Sequel::Model.plugin :prepared_statements

if ENV['RACK_ENV'] == 'production'
  Sequel::Model.plugin :subclasses
  Sequel::Model.freeze_descendents
  DB.freeze
else
  Sequel::Model.cache_associations = false
  Unreloader.require('models') { |f| Sequel::Model.send :camelize, File.basename(f).sub(/\.rb\z/, '') }
  DB.loggers << Logger.new($stdout)
end
