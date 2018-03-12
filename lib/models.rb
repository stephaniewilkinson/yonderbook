# frozen_string_literal: true

require_relative 'db'

Sequel::Model.plugin :auto_validations
Sequel::Model.plugin :prepared_statements

if ENV['RACK_ENV'] == 'development'
  require 'dotenv/load'
  require 'logger'
  logger = Logger.new $stdout
  Sequel::Model.cache_associations = false
  require 'rack/unreloader'
  Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger: logger, reload: true) { App }
  Unreloader.require('models') { |f| Sequel::Model.send :camelize, File.basename(f).sub(/\.rb\z/, '') }
else
  Sequel::Model.plugin :subclasses
  Sequel::Model.freeze_descendents
  DB.freeze
end
