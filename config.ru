# frozen_string_literal: true

require_relative 'app'

Rollbar.configure do |config|
  config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
end

run App.freeze.app
