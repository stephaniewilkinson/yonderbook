# frozen_string_literal: true

require 'dotenv/load'
require 'logger'
require 'pry'
require 'rack/unreloader'

logger = Logger.new $stdout
Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger: logger, reload: true) { App }
Unreloader.require('app.rb') { 'App' }
