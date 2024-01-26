# frozen_string_literal: true

require 'rake'

case ENV.fetch('RACK_ENV', nil)
when 'production', 'staging'
  require 'rollbar'
  Rollbar.configure do |config|
    config.access_token = '0302f64ea01249dfb3084cb21eae862c'
    config.enabled = true
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
