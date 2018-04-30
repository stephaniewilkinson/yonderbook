# frozen_string_literal: true

require 'rollbar'

Rollbar.configure do |config|
  config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
  config.enabled = (ENV['RACK_ENV'] == 'production')
end

case ENV['RACK_ENV']
when 'production'
  require_relative 'app'
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

  Unreloader = Rack::Unreloader.new(
    subclasses: %w[Roda Sequel::Model],
    logger: logger,
    reload: true
  ) { App }
  Unreloader.require('app.rb') { 'App' }
  run Unreloader
end
