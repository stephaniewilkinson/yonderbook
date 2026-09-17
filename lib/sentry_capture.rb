# frozen_string_literal: true

# Outermost middleware: report what the stack above the Roda app raises, then
# get out of the way.
#
# Sentry::Rack::CaptureExceptions used to do this job and was removed because
# it cloned the hub, built a scope holding the full Rack env, and ran session
# tracking on every request -- ~0.2-0.4MB/request that Falcon's fiber model
# never reclaimed. Removing it also removed the only thing watching the four
# pieces of middleware above the app: Rack::HostRedirect, Rack::Attack,
# MemoryLogger and RequestTimeout. An exception in any of them reached Falcon,
# which answered 500 and moved on, with no report attached anywhere.
#
# Rack::Attack is the worst of the four to be blind to: a throttle rule that
# raises fails every request it matches, and since the rule's intended
# behaviour is to return 429s, nothing about the traffic pattern looks wrong.
#
# This keeps the reporting and none of the machinery that caused the original
# problem: no hub clone, no scope, no reference to env held past the call, no
# session tracking, no transaction. capture_exception allocates one event and
# sends it.
class SentryCapture
  # Reports an exception unless something further down the stack already did.
  #
  # The route-block rescue in app.rb captures and then re-raises outside
  # production, where the error_handler plugin would otherwise send a second
  # event for the same exception.
  def self.capture_once(error, **)
    return if error.instance_variable_defined?(:@sentry_captured)

    error.instance_variable_set(:@sentry_captured, true)
    Sentry.capture_exception error, **
  end

  def initialize app
    @app = app
  end

  def call env
    @app.call env
  rescue Exception => e
    # Exception rather than StandardError because the point is to see the
    # failures nobody anticipated, NoMemoryError above all. SIGKILL stays
    # invisible -- nothing in-process can see that one, which is what the
    # Sentry uptime check covers instead.
    self.class.capture_once(e) unless shutdown_or_cancellation?(e)
    raise
  end

  private

  # Falcon cancels tasks on client disconnect and the process takes a SIGTERM
  # on every deploy. Neither is a failure, and both would otherwise open an
  # issue per occurrence.
  def shutdown_or_cancellation? error
    error.is_a?(SystemExit) || error.is_a?(SignalException) || (defined?(Async::Stop) && error.is_a?(Async::Stop))
  end
end
