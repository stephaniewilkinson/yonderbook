# frozen_string_literal: true

require 'rollbar'

Rollbar.configure do |config|
  config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
end

if ENV['RACK_ENV'] == 'production'
  require_relative 'app'
  run App.freeze.app
else
  require 'dotenv/load'
  require 'logger'
  require 'pry'
  require 'rack/unreloader'
  logger = Logger.new $stdout
  Unreloader = Rack::Unreloader.new(
    subclasses: %w[Roda Sequel::Model],
    logger: logger,
    reload: true
  ) { App }
  Unreloader.require('app.rb') { 'App' }
  run Unreloader
end
