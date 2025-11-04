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

# Load database connection first
require_relative '../../lib/database'

# Run migrations for test database (in-memory SQLite) BEFORE loading app/models
Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

# Now load the app (which loads models) - tables exist now
require_relative '../../app'

Capybara.app = App
Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new app, browser: :chrome
end

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-blink-features=AutomationControlled')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--no-sandbox')
  Capybara::Selenium::Driver.new app, browser: :chrome, options: options
end

Capybara.register_driver :firefox do |app|
  Capybara::Selenium::Driver.new app, browser: :firefox
end

Capybara.register_driver :headless_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-blink-features=AutomationControlled')
  options.add_preference('dom.webdriver.enabled', false)
  options.add_preference('useAutomationExtension', false)
  Capybara::Selenium::Driver.new app, browser: :firefox, options: options
end

# Use Firefox in CI (GitHub Actions), Chrome locally (Firefox 144.0 broken on macOS)
driver = ENV['CI'] ? :headless_firefox : :chrome

Capybara.javascript_driver = driver

Capybara.configure do |config|
  config.server = :falcon
  config.run_server = true
  config.server_port = 9292
  config.default_driver = driver
  config.app_host = 'http://localhost:9292'
end

# Helper module for test utilities
module TestHelpers
  # Helper method to manually verify an account in tests
  def verify_account email
    # Wait for account to be created (async operation)
    account = nil
    10.times do
      account = DB[:accounts].where(email: email).first
      break if account

      sleep 0.1
    end

    return unless account

    # Update status to verified (status 2)
    DB[:accounts].where(id: account[:id]).update(status_id: 2)
    # Remove verification key if it exists
    DB[:account_verification_keys].where(id: account[:id]).delete
  end
end

# Include the helper module in Minitest
module Minitest
  class Test
    include TestHelpers
  end
end
