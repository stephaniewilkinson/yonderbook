# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'dotenv/load'
require 'logger'
require 'minitest/autorun'
require 'minitest/capybara'
require 'minitest/pride'
require 'rack/test'
require 'webdrivers/chromedriver'
require_relative '../../app'

Capybara.app = App
Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new app, browser: :chrome
end

Capybara.register_driver :headless_chrome do |app|
  Capybara::Selenium::Driver.new app,
                                 browser: :chrome
end

Capybara.javascript_driver = :chrome

Capybara.configure do |config|
  config.run_server = true
  config.server_port = 9292
  config.default_driver = :chrome
  config.app_host = 'http://localhost:9292'
end
