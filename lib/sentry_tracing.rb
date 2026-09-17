# frozen_string_literal: true

# Opt-in latency measurement for the two route families whose slow paths are
# network calls to services this app does not control.
#
# Tracing was turned off wholesale (traces_sample_rate = 0) because transaction
# objects hold Rack env references and contributed to the RSS growth documented
# in the README. That left the app with no latency data of any kind, which
# matters more here than it would elsewhere: lib/request_timeout.rb caps a
# request at 25s and lib/route_helpers.rb gives the background shelf fetch
# task.with_timeout(20), and both numbers were picked without a distribution to
# pick them from. Whether 20s is generous or tight for a Goodreads shelf fetch
# currently becomes known via user complaint.
#
# Three things keep this different in kind from the blanket rate that was
# removed:
#
# - It only starts a transaction for matching paths, so the homepage and the
#   bot traffic that hits it every minute are untouched.
# - It never puts the transaction on a scope, so there are no child spans and
#   no hub clone. What it measures is end-to-end wall time for the request,
#   which is the number wanted here.
# - It holds no reference to env past the call. The transaction carries a
#   method and a normalized path, nothing else.
#
# It is off unless SENTRY_TRACES_SAMPLE_RATE is set, and the sampler in
# config.ru is a second gate on the same route families. Enable it on staging
# first, watch RSS across a full day including the hour the OOM usually lands,
# and unset the variable to roll back without a deploy. If the curve changes at
# all, that is the answer -- and it turns the comment this replaces from a
# hypothesis into a measurement.
class SentryTracing
  # Goodreads shelf fetches and the OverDrive availability check that hangs off
  # them, which is every route in the app that waits on a third party.
  TRACED_PATH = %r{\A/goodreads/(shelves|availability)}
  # The browser polls these while a background job runs. Tracing them would
  # measure the polling interval rather than the work.
  POLLING_PATH = %r{/(progress|results)\z}
  # Shelf names are user data and would make every shelf its own transaction.
  SHELF_SEGMENT = %r{(?<=/shelves/)[^/]+}

  def initialize app
    @app = app
  end

  def call env
    path = env['PATH_INFO']
    return @app.call(env) unless TRACED_PATH.match?(path) && !POLLING_PATH.match?(path)

    transaction = Sentry.start_transaction(name: "#{env['REQUEST_METHOD']} #{path.sub(SHELF_SEGMENT, ':shelf')}", op: 'http.server')
    return @app.call(env) unless transaction

    begin
      status, headers, body = @app.call(env)
      transaction.set_http_status status
      [status, headers, body]
    ensure
      transaction.finish
    end
  end
end
