# frozen_string_literal: true

# Removes credential-carrying data from Sentry events before they are sent.
#
# This replaces a before_send that checked whether SENTRY_DSN was set. That
# check never dropped anything: Sentry.init with no DSN builds a disabled
# client that sends nothing regardless, so the condition was true whenever an
# event could have been sent at all. It read like a scrubber and sat in the
# position a scrubber occupies.
#
# Two jobs:
#
# 1. Drop request data wholesale. This app posts a BookMooch username and
#    password, runs Rodauth login and account-creation forms, and keeps
#    OAuth tokens in the session, so no allowlist of body keys is safe here --
#    on the routes most likely to raise, the credential *is* the payload.
#    Nothing attaches request data today (the Rack integration is gone, see
#    lib/sentry_capture.rb), which is what makes a wholesale drop free now and
#    a seatbelt later: the moment an upgrade changes a default or a call site
#    passes request.params instead of request.params.keys, this is what stands
#    between that and Sentry's retention window.
#
# 2. Redact sensitive keys everywhere else in the event. extra, contexts and
#    tags are all set by hand -- see enrich_sentry_error in lib/route_helpers
#    -- and a future call site can pass more than it means to.
module SentryScrubber
  SENSITIVE_KEY = /passw|secret|token|api[-_]?key|auth|credential|session|cookie/i
  REDACTED = '[Filtered]'

  module_function

  # Shaped as a before_send / before_send_transaction callback: takes the
  # event and a hint, returns the event to send or nil to drop it.
  def call event, _hint = nil
    scrub_request event.request
    event.extra = scrub(event.extra)
    event.contexts = scrub(event.contexts)
    event.tags = scrub(event.tags)
    event
  end

  def scrub_request request
    return unless request

    request.data = nil
    request.cookies = nil
    request.query_string = nil
    request.env = {}
    request.headers = scrub(request.headers)
  end

  def scrub value
    case value
    when Hash then value.to_h { |k, v| [k, SENSITIVE_KEY.match?(k.to_s) ? REDACTED : scrub(v)] }
    when Array then value.map { |v| scrub v }
    else value
    end
  end
end
