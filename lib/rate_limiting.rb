# frozen_string_literal: true

require 'rack/attack'
require_relative 'throttle_store'

# Per-IP rate limits.
#
# Rodauth's lockout feature caps failed logins per ACCOUNT, but nothing capped
# requests per IP. That left three holes:
#
#   * /sign-up, /reset-password-request and the email-auth endpoints each send
#     mail through Resend. Unthrottled, a loop costs money and burns sending
#     reputation, and can be pointed at someone else's inbox.
#   * Lockout does nothing against credential stuffing spread across many
#     accounts, since each account only ever sees one or two failures.
#   * /search/* reaches the Goodreads API, which was deprecated in 2020 and
#     issues no new keys. Quota burned there cannot be replaced.
module RateLimiting
  # Every path that puts a message in someone's inbox.
  EMAIL_SENDING_PATHS = %w[/sign-up /reset-password-request /email-auth-request /verify-account-resend].freeze

  module_function

  def configure store: ThrottleStore.new
    Rack::Attack.cache.store = store
    safelist_infrastructure
    throttle_email_senders
    throttle_logins
    throttle_search
    throttle_zip_lookups
    throttle_writes
    respond_with_429
    Rack::Attack
  end

  # Render polls /health continuously and assets are served by the app itself.
  # Neither should ever count against a limit.
  def safelist_infrastructure
    Rack::Attack.safelist('health checks and assets') do |request|
      request.path == '/health' || request.path.start_with?('/assets/')
    end
  end

  # Deliberately strict: five emails an hour from one address is already far
  # more than a real person needs, and each one costs money.
  def throttle_email_senders
    Rack::Attack.throttle('email sending endpoints per ip', limit: 5, period: 3600) do |request|
      request.ip if request.post? && EMAIL_SENDING_PATHS.include?(request.path)
    end
  end

  # Catches credential stuffing across many accounts, which per-account lockout
  # cannot see. Loose enough that a household behind one NAT is unaffected.
  def throttle_logins
    Rack::Attack.throttle('logins per ip', limit: 20, period: 300) do |request|
      request.ip if request.post? && request.path == '/authenticate'
    end
  end

  def throttle_search
    Rack::Attack.throttle('search writes per ip', limit: 10, period: 60) do |request|
      request.ip if request.post? && request.path.start_with?('/search')
    end

    Rack::Attack.throttle('search reads per ip', limit: 30, period: 60) do |request|
      request.ip if request.get? && request.path.start_with?('/search')
    end
  end

  # Public, and each call scans 43k zip rows. Cheap individually, worth a cap.
  def throttle_zip_lookups
    Rack::Attack.throttle('zip lookups per ip', limit: 30, period: 60) do |request|
      request.ip if request.path == '/nearest-zip'
    end
  end

  # Backstop so an endpoint added later is never completely unprotected.
  # Generous: no human submits a form once a second for a minute.
  def throttle_writes
    Rack::Attack.throttle('writes per ip', limit: 60, period: 60) do |request|
      request.ip if request.post?
    end
  end

  def respond_with_429
    Rack::Attack.throttled_responder = ->(request) do
      retry_after = request.env.dig('rack.attack.match_data', :period).to_i
      body = "Too many requests. Please wait #{retry_after} seconds and try again.\n"
      [429, {'content-type' => 'text/plain', 'retry-after' => retry_after.to_s}, [body]]
    end
  end
end
