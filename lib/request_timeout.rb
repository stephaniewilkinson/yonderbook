# frozen_string_literal: true

# Rack middleware that enforces a per-request timeout using Async's
# fiber-safe timeout mechanism. Designed for Falcon.
#
# Raises before Render's ~30s proxy timeout kills the connection,
# so the app can report to Sentry instead of silently 502ing.
#
# Skips WebSocket upgrades since those are long-lived connections.
class RequestTimeout
  class Error < StandardError; end

  def initialize app, timeout: 25
    @app = app
    @timeout = timeout
  end

  def call env
    task = defined?(Async::Task) && Async::Task.current?

    if task && !websocket?(env)
      task.with_timeout(@timeout, Error, "#{env['REQUEST_METHOD']} #{env['PATH_INFO']} exceeded #{@timeout}s timeout") do
        @app.call(env)
      end
    else
      @app.call(env)
    end
  end

  private

  def websocket? env
    env['HTTP_UPGRADE']&.casecmp('websocket')&.zero?
  end
end
