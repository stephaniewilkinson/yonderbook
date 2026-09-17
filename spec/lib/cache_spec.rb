# frozen_string_literal: true

require_relative 'spec_helper'
require 'availability_helpers'
require 'cache'
require 'overdrive'
require 'securerandom'

describe Cache do
  before do
    @session_id = "test_#{SecureRandom.hex(8)}"
  end

  after do
    Cache.clear_by_id(@session_id)
  end

  describe '.set_by_id and .get_by_id' do
    it 'round-trips string values' do
      Cache.set_by_id(@session_id, username: 'alice')
      assert_equal 'alice', Cache.get_by_id(@session_id, :username)
    end

    it 'round-trips hashes with symbol keys' do
      data = [{isbn: '123', title: 'Test Book'}]
      Cache.set_by_id(@session_id, book_info: data)
      result = Cache.get_by_id(@session_id, :book_info)
      assert_equal '123', result.first[:isbn]
      assert_equal 'Test Book', result.first[:title]
    end

    it 'returns nil for missing keys' do
      assert_nil Cache.get_by_id(@session_id, :nonexistent)
    end
  end

  describe '.clear_by_id' do
    it 'removes all files for a session' do
      Cache.set_by_id(@session_id, a: 'one', b: 'two')
      Cache.clear_by_id(@session_id)
      assert_nil Cache.get_by_id(@session_id, :a)
      assert_nil Cache.get_by_id(@session_id, :b)
    end
  end

  describe '.get_by_id with corrupt file' do
    it 'returns nil and deletes the corrupt file' do
      Cache.set_by_id(@session_id, bad: 'data')
      path = File.join(Cache::SHARED_DIR, "#{@session_id}_bad.json")
      File.write(path, 'not valid json{{{')

      result = Cache.get_by_id(@session_id, :bad)
      assert_nil result
      refute File.exist?(path), 'Expected corrupt cache file to be deleted'
    end
  end

  describe '.cleanup_stale' do
    it 'removes files older than 1 hour' do
      Cache.set_by_id(@session_id, old: 'data')
      path = File.join(Cache::SHARED_DIR, "#{@session_id}_old.json")
      FileUtils.touch(path, mtime: Time.now - 7200)

      Cache.cleanup_stale
      assert_nil Cache.get_by_id(@session_id, :old)
    end

    it 'keeps recent files' do
      Cache.set_by_id(@session_id, fresh: 'data')
      Cache.cleanup_stale
      assert_equal 'data', Cache.get_by_id(@session_id, :fresh)
    end
  end

  # #1265. An anonymous session holds Goodreads credentials for someone who may
  # never come back, on a 512MB instance. A signed-in one has an account behind
  # it and keeps the longer default.
  describe 'session lifetimes' do
    def anonymous_session = {'session_id' => "anon-#{SecureRandom.hex(6)}"}

    def signed_in_session = {'session_id' => "user-#{SecureRandom.hex(6)}", 'account_id' => 42}

    it 'recognises a session with no account as anonymous' do
      assert Cache.anonymous_session?(anonymous_session)
      refute Cache.anonymous_session?(signed_in_session)
    end

    it 'gives an anonymous session the shorter lifetime' do
      session = anonymous_session
      Cache.set session, shelf_name: 'to-read'

      assert_equal Cache::ANONYMOUS_TTL, Cache.ttl_for(session['session_id'])
    end

    it 'leaves a signed-in session on the default lifetime' do
      session = signed_in_session
      Cache.set session, shelf_name: 'to-read'

      assert_equal Cache::CACHE.expires_in_secs, Cache.ttl_for(session['session_id'])
    end

    # The WebSocket handlers hold a session id and never see the Rack session,
    # so the marker Cache.set leaves behind is how they inherit the right one.
    it 'lets a caller holding only a session id inherit the lifetime' do
      session = anonymous_session
      Cache.set session, shelf_name: 'to-read'

      Cache.set_in_session session['session_id'], titles: %w[a b]

      assert_equal Cache::ANONYMOUS_TTL, Cache.ttl_for(session['session_id'])
      assert_equal %w[a b], Cache.get_in_session(session['session_id'], :titles)
    end

    it 'defaults an unmarked session id to the longer lifetime' do
      # Shortening a signed-in session by accident is the worse mistake.
      assert_equal Cache::CACHE.expires_in_secs, Cache.ttl_for("never-seen-#{SecureRandom.hex(4)}")
    end
  end

  describe 'filesystem cleanup' do
    def stamp_path = File.join(Cache::SHARED_DIR, Cache::CLEANUP_STAMP)

    before do
      FileUtils.mkdir_p Cache::SHARED_DIR
      FileUtils.rm_f stamp_path
    end

    it 'is due when it has never run' do
      assert Cache.cleanup_due?
    end

    # The old trigger was a module-level request counter. Falcon runs several
    # processes, each kept its own count, so on a quiet day files outlived the
    # cutoff by a wide margin. An mtime is shared by every process.
    it 'is not due again immediately after running' do
      Cache.cleanup_stale

      refute Cache.cleanup_due?
    end

    it 'is due again once the interval has passed' do
      Cache.cleanup_stale
      old = Time.now - Cache::CLEANUP_INTERVAL - 60
      File.utime old, old, stamp_path

      assert Cache.cleanup_due?
    end

    it 'expires an anonymous entry sooner than a signed-in one' do
      session_id = "ttl-#{SecureRandom.hex(6)}"
      Cache.set_by_id session_id, anonymous: true, shelf: %w[a]
      Cache.set_by_id "#{session_id}-user", shelf: %w[a]

      anon = Cache.path_for(session_id, :shelf, anonymous: true)
      user = Cache.path_for("#{session_id}-user", :shelf)
      # Both older than the anonymous cutoff, neither older than an hour.
      aged = Time.now - Cache::ANONYMOUS_TTL - 60
      [anon, user].each { |f| File.utime aged, aged, f }

      Cache.cleanup_stale

      refute_path_exists anon, 'the anonymous entry outlived its cutoff'
      assert_path_exists user, 'the signed-in entry was expired early'
    end

    it 'reads an entry back whichever way it was written' do
      session_id = "read-#{SecureRandom.hex(6)}"
      Cache.set_by_id session_id, anonymous: true, books: [{isbn: '1'}]

      assert_equal [{isbn: '1'}], Cache.get_by_id(session_id, :books)
    end

    it 'clears both namings for a session' do
      session_id = "clear-#{SecureRandom.hex(6)}"
      Cache.set_by_id session_id, anonymous: true, books: %w[a]
      Cache.set_by_id session_id, other: %w[b]

      Cache.clear_by_id session_id

      assert_nil Cache.get_by_id(session_id, :books)
      assert_nil Cache.get_by_id(session_id, :other)
    end
  end

  # #1390. The cap is enforced server-side as well as in the picker: the form
  # is the polite version, not the guarantee.
  describe 'choosing libraries' do
    # A stand-in for the Roda instance: chosen_libraries reads params and the
    # session cache, and nothing else.
    class LibraryChooser
      include AvailabilityHelpers

      attr_accessor :session
    end

    FakeParams = Struct.new(:params)

    def chooser_for session_id
      LibraryChooser.new.tap { |chooser| chooser.session = {'session_id' => session_id} }
    end

    def nearby = [%w[1135 Brooklyn], %w[4242 NYPL], %w[7 Queens], %w[8 Jersey]]

    it 'pairs each chosen id with its name' do
      session_id = "lib-#{SecureRandom.hex(4)}"
      Cache.set_in_session session_id, libraries: nearby

      chosen = chooser_for(session_id).chosen_libraries FakeParams.new({'consortium' => %w[4242 1135]})

      assert_equal [%w[1135 Brooklyn], %w[4242 NYPL]], chosen
    end

    it 'caps the number of libraries' do
      session_id = "lib-#{SecureRandom.hex(4)}"
      Cache.set_in_session session_id, libraries: nearby

      chosen = chooser_for(session_id).chosen_libraries FakeParams.new({'consortium' => %w[1135 4242 7 8]})

      assert_equal AvailabilityHelpers::MAX_LIBRARIES, chosen.size
    end

    it 'ignores an id that was not among the libraries offered' do
      session_id = "lib-#{SecureRandom.hex(4)}"
      Cache.set_in_session session_id, libraries: nearby

      chosen = chooser_for(session_id).chosen_libraries FakeParams.new({'consortium' => %w[9999]})

      assert_empty chosen
    end

    it 'returns nothing when none were chosen' do
      session_id = "lib-#{SecureRandom.hex(4)}"
      Cache.set_in_session session_id, libraries: nearby

      assert_empty chooser_for(session_id).chosen_libraries(FakeParams.new({}))
    end
  end
end
