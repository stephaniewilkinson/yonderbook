# frozen_string_literal: true

require 'dotenv/load'
require 'logger'
require 'pry'
require 'minitest/capybara'
require "selenium/webdriver"

logger = Logger.new $stdout


Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, browser: :chrome)
end

Capybara.register_driver :headless_chrome do |app|
  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: { args: %w(headless disable-gpu) }
  )

  Capybara::Selenium::Driver.new app,
    browser: :chrome,
    desired_capabilities: capabilities
end

Capybara.javascript_driver = :chrome

Capybara.configure do |config|
  config.run_server = false
  config.default_driver = :headless_chrome
  config.app_host = 'http://localhost:9292'
end
