# frozen_string_literal: true

case ENV.fetch('RACK_ENV', nil)
when 'production', 'staging'
  require 'sentry-ruby'

  Sentry.init do |config|
    config.dsn = 'https://22a8f30b43dede96513c7638fdd0110e@o4510085954666496.ingest.us.sentry.io/4510085957353472'
    config.send_default_pii = true
  end

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
