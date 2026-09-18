# frozen_string_literal: true

# Redacts credential *values* out of text, wherever they turn up.
#
# The scrubber in lib/sentry_scrubber.rb works by key name -- it drops
# `request.data`, redacts anything called `password` -- which handles
# structured data. It cannot help with free text, and the most likely leak here
# is exactly that: the Goodreads key travels as a query parameter
# (`/review/list/42.xml?key=<KEY>&...`, lib/goodreads.rb:61), so any exception
# raised mid-request tends to carry it inside the message string, which then
# goes to Sentry and to stderr verbatim.
#
# This matches on the secret itself instead, so it does not matter whether the
# value shows up in an exception message, a backtrace line, a log line or a
# breadcrumb.
#
# The Goodreads key is the one that matters most: Amazon deprecated the API in
# 2020 and issues no new keys, so a leaked one that gets revoked is gone for
# good rather than rotated.
module Secrets
  # Values of these are never allowed to appear in output.
  #
  # Deliberately not GOODREADS_USER_ID (not secret, and "1" would corrupt every
  # log line) or BOOKMOOCH_USERNAME (a username, and a short common word would
  # mangle book titles). The password is what matters on that pair.
  GUARDED = %w[
    GOODREADS_API_KEY
    GOODREADS_SECRET
    GOODREADS_ACCESS_TOKEN
    GOODREADS_ACCESS_TOKEN_SECRET
    GOODREADS_PASSWORD
    OVERDRIVE_KEY
    OVERDRIVE_SECRET
    BOOKMOOCH_PASSWORD
    RESEND_API_KEY
    SESSION_SECRET
    SENTRY_DSN
  ].freeze

  # Below this, a value is more likely to be a placeholder or a common word
  # than a credential, and redacting it would do more damage than the leak.
  MIN_LENGTH = 8

  PLACEHOLDER = '[REDACTED]'

  module_function

  # Longest first, so a secret that contains another is replaced whole rather
  # than left half-redacted.
  def values
    @values ||= GUARDED.filter_map { |name| ENV.fetch(name, nil) }.select { |value| value.length >= MIN_LENGTH }.uniq.sort_by { |value| -value.length }
  end

  # Call after changing ENV, which in practice means specs.
  def reset!
    @values = nil
  end

  def redact text
    return text unless text.is_a?(String)
    return text if values.empty?

    values.reduce(text) { |acc, elem| acc.gsub(elem, PLACEHOLDER) }
  end
end
