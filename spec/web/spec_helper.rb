# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'dotenv/load'
require 'falcon/capybara'
require 'logger'
require 'minitest/autorun'
require 'minitest/capybara'
require 'minitest/pride'
require 'rack/test'
require 'selenium-webdriver'

require_relative '../../app'

# Run migrations for test database (in-memory SQLite)
Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

Capybara.app = App
Capybara.register_driver :firefox do |app|
  Capybara::Selenium::Driver.new app, browser: :firefox
end

Capybara.register_driver :headless_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('--headless')
  Capybara::Selenium::Driver.new app, browser: :firefox, options: options
end

# Use headless Firefox in CI environments
driver = ENV['CI'] ? :headless_firefox : :firefox

Capybara.javascript_driver = driver

Capybara.configure do |config|
  config.server = :falcon
  config.run_server = true
  config.server_port = 9292
  config.default_driver = driver
  config.app_host = 'http://localhost:9292'
end
