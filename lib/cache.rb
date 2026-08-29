# frozen_string_literal: true

require 'async'
require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'tuple_space'

module Cache
  CACHE = TupleSpace.new
  SHARED_DIR = File.join(Dir.tmpdir, 'yonderbook_jobs')
  @request_count = 0

  module_function

  def set session, **pairs
    set_in_session session['session_id'], **pairs
  end

  def get session, key
    get_in_session session['session_id'], key
  end

  # Same in-memory store as `set`/`get`, for callers holding a session id rather
  # than the session itself -- WebSocket handlers never see the Rack session.
  #
  # Deliberately not `set_by_id`, which serialises through JSON on disk. The
  # availability titles are objects the view calls methods on, and a JSON round
  # trip would hand it bare hashes. Nothing here touches the filesystem, so
  # OAuth tokens stored this way stay in memory.
  def set_in_session session_id, **pairs
    pairs.each do |key, value|
      CACHE["#{session_id}/#{key}"] = value
    end
  end

  def get_in_session session_id, key
    CACHE["#{session_id}/#{key}"]
  end

  # Set cache values by session ID using shared filesystem (cross-process)
  def set_by_id session_id, **pairs
    FileUtils.mkdir_p(SHARED_DIR)
    @request_count = (@request_count + 1) % 100
    cleanup_stale_async if @request_count.zero?
    pairs.each do |key, value|
      path = File.join(SHARED_DIR, "#{session_id}_#{key}.json")
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.generate(value))
      File.rename(tmp, path)
    end
  end

  # Get cache value by session ID from shared filesystem (cross-process)
  def get_by_id session_id, key
    path = File.join(SHARED_DIR, "#{session_id}_#{key}.json")
    return unless File.exist?(path)

    JSON.parse(File.read(path), symbolize_names: true)
  rescue JSON::ParserError
    File.delete(path)
    nil
  end

  # Remove cache files for a session after use
  def clear_by_id session_id
    return unless Dir.exist?(SHARED_DIR)

    Dir.glob(File.join(SHARED_DIR, "#{session_id}_*.json")).each { |f| File.delete(f) }
  end

  # Run cleanup in a background fiber so it doesn't block the current request
  def cleanup_stale_async
    return cleanup_stale unless Fiber.scheduler

    Async::Task.current.async { cleanup_stale }
  end

  # Remove cache files older than 1 hour
  def cleanup_stale
    return unless Dir.exist?(SHARED_DIR)

    cutoff = Time.now - 3600
    Dir.glob(File.join(SHARED_DIR, '*.json')).each { |f| File.delete(f) if File.mtime(f) < cutoff }
  end
end
