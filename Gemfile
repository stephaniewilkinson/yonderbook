# frozen_string_literal: true

source 'https://gem.coop'

ruby File.read(File.join(__dir__, '.ruby-version')).chomp.delete_prefix('ruby-')

gem 'area'
gem 'argon2'
gem 'async-http'
gem 'async-limiter'
gem 'bcrypt'
gem 'dotenv'
gem 'drb'
gem 'falcon'
gem 'gender_detector'
gem 'i18n', '>= 1'
gem 'mail'
gem 'nokogiri'
gem 'oauth'
gem 'oauth2'
gem 'posthog-ruby'
gem 'rack-host-redirect'
gem 'rake'
gem 'resend'
gem 'rinda'
gem 'roda'
gem 'rodauth'
gem 'roda-websockets'
gem 'sentry-ruby'
gem 'sequel'
gem 'sqlite3'
gem 'tilt'
gem 'unicode_utils'

group :development do
  gem 'rack-unreloader'
  gem 'rackup'
  gem 'roda-route_list'
  gem 'tailwindcss-ruby'
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
  gem 'falcon-capybara'
  gem 'minitest'
  gem 'minitest-capybara'
  gem 'rack-test'
end
