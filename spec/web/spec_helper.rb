# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'dotenv/load'
require 'logger'
require 'minitest/autorun'
require 'minitest/capybara'
require 'minitest/pride'
require 'rack/test'
require 'webdrivers/geckodriver'
require_relative '../../app'

Capybara.app = App
Capybara.register_driver :firefox do |app|
  Capybara::Selenium::Driver.new app, browser: :firefox
end

Capybara.register_driver :headless_firefox do |app|
  Capybara::Selenium::Driver.new app,
                                 browser: :firefox
end

Capybara.javascript_driver = :firefox

Capybara.configure do |config|
  config.run_server = true
  config.server_port = 9292
  config.default_driver = :firefox
  config.app_host = 'http://localhost:9292'
end
