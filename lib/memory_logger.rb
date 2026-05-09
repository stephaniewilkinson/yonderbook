# frozen_string_literal: true

# Rack middleware that logs RSS memory and GC stats on every request.
# Designed to diagnose OOM kills on Render (512MB). Since SIGKILL
# cannot be caught, we log BEFORE and AFTER each request so the
# trend leading up to the crash is visible in Render's log drain.
#
# If a request causes OOM, the "start" line will appear with no
# matching "end" line -- that identifies the killing request.
class MemoryLogger
  def initialize app
    @app = app
    @request_number = 0
  end

  def call env
    @request_number += 1
    rid = @request_number
    method = env['REQUEST_METHOD']
    path = env['PATH_INFO']

    # Skip noisy health checks and static assets
    return @app.call(env) if path == '/health' || path.start_with?('/assets/', '/favicon')

    rss_before = rss_mb
    warn "[mem] ##{rid} START #{method} #{path} rss=#{rss_before}MB"

    gc_before = GC.stat
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)

    rss_after = rss_mb
    gc_after = GC.stat
    delta = (rss_after - rss_before).round(1)
    delta_str = delta >= 0 ? "+#{delta}" : delta.to_s

    warn "[mem] ##{rid} END #{method} #{path} status=#{status} duration=#{duration}ms " \
         "rss=#{rss_after}MB delta=#{delta_str}MB heap_live=#{gc_after[:heap_live_slots]} " \
         "old_objects=#{gc_after[:old_objects]} major_gc=#{gc_after[:major_gc_count] - gc_before[:major_gc_count]} " \
         "minor_gc=#{gc_after[:minor_gc_count] - gc_before[:minor_gc_count]}"

    warn "[mem] WARNING: RSS at #{rss_after}MB -- approaching 512MB OOM threshold" if rss_after > 400

    [status, headers, body]
  end

  private

  def rss_mb
    if File.exist?('/proc/self/status')
      # Linux (Render) -- read VmRSS in kB
      File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_f / 1024
    else
      # macOS fallback
      `ps -o rss= -p #{Process.pid}`.strip.to_f / 1024
    end.round(1)
  end
end
