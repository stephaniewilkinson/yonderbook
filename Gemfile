# frozen_string_literal: true

source 'https://gem.coop'

ruby File.read(File.join(__dir__, '.ruby-version')).chomp.delete_prefix('ruby-')

gem 'area'
gem 'async-http'
gem 'bcrypt'
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
gem 'rinda'
gem 'roda'
gem 'rodauth'
gem 'sentry-ruby'
gem 'sequel'
gem 'sqlite3'
gem 'tilt'
gem 'unicode_utils'

group :development do
  gem 'rack-unreloader'
  gem 'roda-route_list'
end

group :development, :test do
  gem 'pry'
  gem 'rubocop'
  gem 'rubocop-minitest'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
  gem 'rubocop-sequel'
end

group :test do
  gem 'capybara-selenium'
  gem 'minitest'
  gem 'minitest-capybara'
  gem 'rack-test'
end
