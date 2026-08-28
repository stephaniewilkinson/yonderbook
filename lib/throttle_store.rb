# frozen_string_literal: true

# Minimal in-memory counter store for Rack::Attack.
#
# Rack::Attack's usual in-process backend is ActiveSupport::Cache::MemoryStore,
# and pulling ActiveSupport in for a handful of counters is a poor trade on a
# 512MB instance with a documented OOM problem. This holds nothing but integers
# and their expiry, and prunes expired entries so a flood of distinct IPs cannot
# grow it without bound.
#
# Counters are per-process. Falcon runs a single threaded container here, so
# that is the whole app; if the service ever runs multiple processes, each keeps
# its own counts and the effective limit multiplies by the process count.
class ThrottleStore
  # Pruning every write would be O(n) on the hot path. Amortize it instead.
  PRUNE_EVERY = 500

  def initialize
    @data = {}
    @mutex = Mutex.new
    @writes = 0
  end

  def increment key, amount = 1, expires_in: nil
    @mutex.synchronize do
      maybe_prune
      store key, (fetch(key) || 0) + amount, expires_in
    end
  end

  def write key, value, expires_in: nil
    @mutex.synchronize do
      maybe_prune
      store key, value, expires_in
    end
  end

  def read key
    @mutex.synchronize { fetch key }
  end

  def delete key
    @mutex.synchronize { @data.delete key }
    nil
  end

  # Rack::Attack.reset! calls this with a glob like "rack::attack*".
  def delete_matched pattern
    prefix = pattern.to_s.delete_suffix('*')
    @mutex.synchronize { @data.delete_if { |key, _value| key.start_with? prefix } }
    nil
  end

  # Exposed so a spec can assert that expired entries are actually reclaimed.
  def size
    @mutex.synchronize { @data.size }
  end

  private

  def store key, value, expires_in
    @data[key] = [value, expires_in ? now + expires_in : nil]
    value
  end

  def fetch key
    value, expires_at = @data[key]
    return if value.nil?

    if expires_at && expires_at <= now
      @data.delete key
      return
    end

    value
  end

  def maybe_prune
    @writes += 1
    return if (@writes % PRUNE_EVERY).nonzero?

    cutoff = now
    @data.delete_if { |_key, (_value, expires_at)| expires_at && expires_at <= cutoff }
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
