# frozen_string_literal: true

# Initialize Sentry for all environments
require 'sentry-ruby'

Sentry.init do |config|
  config.dsn = ENV.fetch('SENTRY_DSN', nil)
  config.environment = ENV.fetch('RACK_ENV', 'development')
  config.enabled_environments = %w[development test production staging]
  config.send_default_pii = true

  # Send errors from all environments to ensure tracking works
  config.traces_sample_rate = ENV['RACK_ENV'] == 'production' ? 0.1 : 1.0

  # Don't send errors if DSN is not configured
  config.before_send = ->(event, _hint) do
    event if ENV['SENTRY_DSN'] && !ENV['SENTRY_DSN'].empty?
  end
end

case ENV.fetch('RACK_ENV', nil)
when 'production', 'staging'
  require_relative 'app'
  logger = Logger.new $stdout
  logger.level = Logger::DEBUG
  run App.freeze.app
when 'test'
  require 'dotenv/load'
  require 'pry'
  require_relative 'app'
  logger = Logger.new('logger.log', 'daily')
  logger.level = Logger::DEBUG
  run App.freeze.app
else
  require 'dotenv/load'
  require 'logger'
  require 'pry'
  require 'rack/unreloader'
  logger = Logger.new $stdout
  logger.level = Logger::DEBUG

  Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger:, reload: true) { App }
  Unreloader.require('app.rb') { 'App' }
  run Unreloader
end
