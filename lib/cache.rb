# frozen_string_literal: true

require 'async'
require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'tuple_space'

module Cache
  CACHE = TupleSpace.new
  SHARED_DIR = File.join(Dir.tmpdir, 'yonderbook_jobs')

  # An anonymous session's data is held on a 512MB instance for someone who may
  # never come back, and it carries Goodreads credentials. A signed-in session
  # has an account behind it and keeps the longer default.
  ANONYMOUS_TTL = 900
  # Marks a filesystem entry as anonymous. Dot-prefixed rather than a separate
  # directory so the existing `#{session_id}_*.json` glob in clear_by_id keeps
  # matching both kinds.
  ANONYMOUS_SUFFIX = '.anon'
  # Key under which a session records whether it is anonymous.
  ANONYMOUS_MARKER = '__anonymous'
  # How often cleanup_stale is allowed to run, coordinated through the mtime of
  # a sentinel file. This replaced a module-level request counter: Falcon runs
  # several processes, each kept its own count, and on a quiet day files
  # outlived the cutoff by a wide margin.
  CLEANUP_INTERVAL = 300
  CLEANUP_STAMP = '.last_cleanup'

  module_function

  # Rodauth puts account_id in the session on login, so its absence is what
  # "anonymous" means here.
  def anonymous_session?(session) = session['account_id'].nil?

  def set session, **pairs
    session_id = session['session_id']
    # Record which kind of session this is, so callers holding only a session
    # id -- the WebSocket handlers -- pick the same lifetime without having to
    # be told. Written with the longer TTL on purpose: if the marker expired
    # first, later writes would silently revert to the signed-in lifetime.
    CACHE.store "#{session_id}/#{ANONYMOUS_MARKER}", anonymous_session?(session), expires_in_secs: CACHE.expires_in_secs
    set_in_session session_id, **pairs
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
  def set_in_session session_id, expires_in_secs: nil, **pairs
    ttl = expires_in_secs || ttl_for(session_id)
    pairs.each do |key, value|
      CACHE.store "#{session_id}/#{key}", value, expires_in_secs: ttl
    end
  end

  # An unmarked session gets the longer lifetime. Shortening a signed-in
  # session by accident is the worse of the two mistakes.
  def ttl_for session_id
    CACHE["#{session_id}/#{ANONYMOUS_MARKER}"] ? ANONYMOUS_TTL : CACHE.expires_in_secs
  end

  def get_in_session session_id, key
    CACHE["#{session_id}/#{key}"]
  end

  # Set cache values by session ID using shared filesystem (cross-process).
  #
  # `anonymous:` marks the entry for the shorter cutoff in cleanup_stale.
  def set_by_id session_id, anonymous: false, **pairs
    FileUtils.mkdir_p(SHARED_DIR)
    cleanup_stale_async if cleanup_due?
    pairs.each do |key, value|
      path = path_for(session_id, key, anonymous: anonymous)
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.generate(value))
      File.rename(tmp, path)
    end
  end

  def path_for session_id, key, anonymous: false
    suffix = anonymous ? ANONYMOUS_SUFFIX : ''
    File.join(SHARED_DIR, "#{session_id}_#{key}#{suffix}.json")
  end

  # Get cache value by session ID from shared filesystem (cross-process).
  #
  # Checks both namings, so a caller never has to know whether the session that
  # wrote the entry was signed in.
  def get_by_id session_id, key
    path = [false, true].map { |anon| path_for(session_id, key, anonymous: anon) }.find { |candidate| File.exist?(candidate) }
    return unless path

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

  # True at most once per CLEANUP_INTERVAL across every process, because the
  # answer lives in a file's mtime rather than in each process's memory.
  def cleanup_due?
    stamp = File.join(SHARED_DIR, CLEANUP_STAMP)
    return true unless File.exist?(stamp)

    File.mtime(stamp) < Time.now - CLEANUP_INTERVAL
  rescue Errno::ENOENT
    true
  end

  # Remove cache files past their cutoff: an hour for a signed-in session,
  # ANONYMOUS_TTL for one that was not.
  def cleanup_stale
    return unless Dir.exist?(SHARED_DIR)

    touch_cleanup_stamp
    now = Time.now
    Dir.glob(File.join(SHARED_DIR, '*.json')).each do |file|
      cutoff = File.basename(file).include?("#{ANONYMOUS_SUFFIX}.json") ? now - ANONYMOUS_TTL : now - 3600
      File.delete(file) if File.mtime(file) < cutoff
    rescue Errno::ENOENT
      nil # another process got there first
    end
  end

  # Written before the sweep, not after, so a long sweep cannot let a second
  # process start another one behind it.
  def touch_cleanup_stamp
    FileUtils.mkdir_p(SHARED_DIR)
    FileUtils.touch File.join(SHARED_DIR, CLEANUP_STAMP)
  end
end
