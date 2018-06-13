# frozen_string_literal: true

source 'https://rubygems.org'

ruby '2.5.1'

gem 'area'
# TODO: try unpinning this version, i think its okay now
gem 'dotenv', '2.2.2' # pinning to a version cuz codeship breaks at 2.4.0
gem 'http'
gem 'nokogiri'
gem 'oauth'
gem 'oauth2'
gem 'pry'
gem 'puma'
gem 'rack-unreloader'
gem 'rack'
gem 'rake'
gem 'roda'
gem 'rubocop'
gem 'sendgrid-ruby'
gem 'sequel_pg'
gem 'sequel'
gem 'tilt'
gem 'typhoeus'
gem 'zbar'

group :test do
  gem 'capybara-selenium'
  gem 'chromedriver-helper'
  gem 'minitest'
  gem 'minitest-capybara'
  gem 'rack-test'
end

group :production do
  gem 'rollbar'
end
