# frozen_string_literal: true

source 'https://rubygems.org'

ruby File.read(File.join(__dir__, '.ruby-version')).chomp.delete_prefix('ruby-')

gem 'area'
gem 'async-http'
gem 'csv'
gem 'dotenv'
gem 'drb'
gem 'falcon'
gem 'falcon-capybara'
gem 'gender_detector'
gem 'i18n', '>= 1'
gem 'mail'
gem 'nokogiri'
gem 'oauth'
gem 'oauth2'
gem 'ostruct'
gem 'rack-host-redirect'
gem 'rackup'
gem 'rake'
gem 'roda'
gem 'tilt'
gem 'unicode_utils'

group :development do
  gem 'rack-unreloader'
  gem 'roda-route_list'
end

group :development, :test do
  gem 'pry'
  gem 'rubocop'
  gem 'rubocop-performance'
end

group :test do
  gem 'capybara-selenium'
  gem 'minitest'
  gem 'minitest-capybara'
  gem 'rack-test'
  gem 'webdrivers'
end

group :production do
  gem 'sentry-ruby'
end
