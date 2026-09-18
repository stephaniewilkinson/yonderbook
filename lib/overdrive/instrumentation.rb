# frozen_string_literal: true

# Timing, memory and progress reporting for an availability check.
#
# Separate from the client because it is a different job: the rest of Overdrive
# talks to an API, this watches how long that takes and how much memory it
# costs. Those numbers are the reference the README's OOM section is written
# against, which is why they are worth keeping rather than folding into a
# logger call.
class Overdrive
  def self.rss_mb
    status_path = "/proc/#{Process.pid}/status"
    kb = File.exist?(status_path) ? File.read(status_path)[/VmRSS:\s+(\d+)/, 1].to_i : `ps -o rss= -p #{Process.pid}`.to_i
    kb / 1024.0
  rescue StandardError
    0.0
  end

  private

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # A failure to report progress must never lose the availability results the
  # chunk just produced -- the socket may have closed while this ran.
  def report_chunk_progress callback, completed, total
    callback&.call(type: 'progress', message: "Checking availability — #{completed} of #{total} batches complete...", current: completed, total: total)
  rescue StandardError
    nil
  end

  def record_timings rss_before, total_start, chunk_count, titles_count
    elapsed = (monotonic_now - total_start).round(2)
    rss_after = self.class.rss_mb.round(1)
    delta = (rss_after - rss_before).round(1)
    @timings = {
      total_books: @book_info.size,
      chunk_count:,
      total_elapsed: elapsed,
      rss_before: rss_before.round(1),
      rss_after:,
      rss_delta: delta,
      titles_returned: titles_count
    }
    warn "[overdrive] Done: #{elapsed}s, #{titles_count} titles, RSS #{rss_before.round(1)}->#{rss_after}MB (delta #{delta}MB)"
  end
end
