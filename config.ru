# frozen_string_literal: true

require 'rollbar'
require_relative 'app'
require_relative 'lib/models'

Rollbar.configure do |config|
  config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
end

if ENV['RACK_ENV'] == 'development'
  require 'dotenv/load'
  require 'logger'
  require 'pry'
  require 'rack/unreloader'
  logger = Logger.new $stdout
  Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger: logger, reload: dev) { App }
  Unreloader.require('app.rb') { 'App' }
  run Unreloader
else
  run App.freeze.app
end
