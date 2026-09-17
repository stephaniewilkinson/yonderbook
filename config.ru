# frozen_string_literal: true

# Initialize Sentry for all environments
require 'sentry-ruby'
require_relative 'lib/sentry_scrubber'

Sentry.init do |config|
  config.dsn = ENV.fetch('SENTRY_DSN', nil)
  config.environment = ENV.fetch('RACK_ENV', 'development')
  config.enabled_environments = %w[development test production staging]

  # Render exports the deployed commit into the runtime environment. Without it
  # every event belongs to the same unnamed version, which costs regression
  # detection (Sentry reopens an issue when it reappears in a release later
  # than the one that resolved it), "first seen in" as a deploy rather than a
  # timestamp, and suspect-commit attribution. Nil locally, as before.
  config.release = ENV.fetch('RENDER_GIT_COMMIT', nil)

  # Default. Turning it on attached request bodies, cookies and IPs to any
  # event that carried request data -- on an app whose login, account-creation
  # and BookMooch import routes all post credentials.
  config.send_default_pii = false

  # See lib/sentry_scrubber.rb. Not load-bearing while nothing attaches request
  # data; it is what keeps that true.
  config.before_send = SentryScrubber.method(:call)
  config.before_send_transaction = SentryScrubber.method(:call)

  # Tracing is off unless SENTRY_TRACES_SAMPLE_RATE is set, and eligible for
  # only the two route families with uncontrolled network calls behind them.
  # Transaction objects hold Rack env references and contributed to the RSS
  # growth on the 512MB Render instance, so this is opt-in per environment
  # rather than a blanket rate -- see lib/sentry_tracing.rb, which is the only
  # thing that starts a transaction and applies the same route filter.
  traces_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', '0').to_f
  config.traces_sampler = ->(context) do
    name = context[:transaction_context][:name].to_s
    next 0.0 unless name.include?('overdrive') || name.include?('shelves') || name.include?('availability')

    traces_rate
  end
end

require 'console'
Console.logger.level = :warn

case ENV.fetch('RACK_ENV', nil)
when 'production', 'staging'
  require_relative 'app'
  require_relative 'lib/memory_logger'
  require_relative 'lib/rate_limiting'
  require_relative 'lib/request_timeout'
  require_relative 'lib/sentry_tracing'
  logger = Logger.new $stdout
  logger.level = Logger::WARN
  # Outermost, so it sees what every other middleware raises. A rescue and a
  # re-raise, nothing else -- it costs a throttled request one stack frame.
  use SentryCapture
  # Next in the stack: a throttled request should cost as little as possible,
  # and never reach session decryption or analytics. Production and staging
  # only -- the test suite drives hundreds of logins from one address, and the
  # rules are covered directly in spec/lib/rate_limiting_spec.rb.
  RateLimiting.configure
  use Rack::Attack
  use MemoryLogger
  use RequestTimeout
  # Innermost, so it measures the route rather than the middleware above it.
  # No-ops unless SENTRY_TRACES_SAMPLE_RATE is set.
  use SentryTracing
  Process.warmup
  run App.freeze.app
when 'test'
  require 'dotenv/load'
  require 'pry'
  require_relative 'app'
  logger = Logger.new('logger.log', 'daily')
  logger.level = Logger::DEBUG
  run App.freeze.app
else
  require 'dotenv/load'
  require 'logger'
  require 'pry'
  require 'rack/unreloader'
  logger = Logger.new $stdout
  logger.level = Logger::DEBUG

  Unreloader = Rack::Unreloader.new(subclasses: %w[Roda Sequel::Model], logger:, reload: true) { App }
  Unreloader.require('app.rb') { 'App' }
  run Unreloader
end
