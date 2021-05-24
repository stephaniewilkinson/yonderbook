# frozen_string_literal: true

case ENV['RACK_ENV']
when 'production', 'staging'
  require 'rollbar'
  Rollbar.configure do |config|
    config.access_token = '83f1303f9940479bb34a23e006c8886d'
    config.enabled = true
  end
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

  Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger: logger, reload: true) { App }
  Unreloader.require('app.rb') { 'App' }
  run Unreloader
end
