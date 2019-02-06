# frozen_string_literal: true

source 'https://rubygems.org'

ruby File.read(File.join(__dir__, '.ruby-version')).chomp.delete_prefix('ruby-')

gem 'area'
gem 'dotenv'
gem 'gender_detector'
gem 'i18n', '>= 1'
gem 'nokogiri'
gem 'oauth'
gem 'oauth2'
gem 'puma'
gem 'rack-host-redirect'
gem 'rake'
gem 'roda'
gem 'roda-message_bus'
gem 'sendgrid-ruby'
gem 'sequel'
gem 'sequel_pg'
gem 'tilt'
gem 'typhoeus'
gem 'unicode_utils'
gem 'zbar'

group :development do
  gem 'rack-unreloader'
  gem 'roda-route_list'
end

group :development, :test do
  gem 'pry'
  gem 'rubocop'
end

group :test do
  gem 'capybara-selenium'
  gem 'chromedriver-helper', '~> 1.0'
  gem 'minitest'
  gem 'minitest-capybara'
  gem 'rack-test'
end

group :production do
  gem 'rollbar'
end
