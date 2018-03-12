# frozen_string_literal: true

dev = ENV['RACK_ENV'] == 'development'

if dev
  require 'dotenv/load'
  require 'logger'
  require 'pry'
  require 'rack/unreloader'
  logger = Logger.new $stdout
  Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger: logger, reload: dev) { App }
  Unreloader.require('app.rb') { 'App' }
end

require_relative 'lib/models'

Rollbar.configure do |config|
  config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
end

run(dev ? Unreloader : App.freeze.app)
