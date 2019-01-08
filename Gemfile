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
gem 'pry'
gem 'puma'
gem 'rake'
gem 'roda'
gem 'sendgrid-ruby'
gem 'sequel_pg'
gem 'sequel'
gem 'tilt'
gem 'typhoeus'
gem 'unicode_utils'
gem 'zbar'

group :development do
  gem 'rack-unreloader'
  gem 'roda-route_list'
end

group :development, :test do
  gem 'rubocop'
end

group :test do
  gem 'capybara-selenium'
  gem 'chromedriver-helper', '~> 1.0'
  gem 'minitest-capybara'
  gem 'minitest'
  gem 'rack-test'
end

group :production do
  gem 'rollbar'
end
