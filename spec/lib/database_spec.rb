# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'
require 'tmpdir'

# Regression: SQLite3::BusyException "database is locked" reaching Sentry from
# app.rb's route block. Sequel's :timeout retried while holding the GVL, which
# starved the lock holder so the wait was guaranteed to run out.
#
# Both cases below fail against the old configuration: the first after the full
# timeout, the second instantly.
describe 'concurrent SQLite writers' do
  # Falcon gives each thread its own connection, so contention needs a
  # file-backed database. These options mirror lib/database.rb.
  def with_file_database
    Dir.mktmpdir do |dir|
      db = Sequel.sqlite(
        File.join(dir, 'test.db'),
        foreign_keys: true,
        synchronous: :normal,
        temp_store: :memory,
        after_connect: proc { |conn| conn.busy_handler_timeout = 10_000 }
      )
      db.run 'PRAGMA journal_mode = WAL'
      db.transaction_mode = :immediate
      db.create_table(:widgets) { primary_key :id }
      begin
        yield db
      ensure
        db.disconnect
      end
    end
  end

  # Runs every block on its own thread and connection, collecting what they
  # raise. Nothing re-raises: each block has to finish for the assertions to
  # mean anything.
  def errors_from *blocks
    errors = []
    mutex = Mutex.new
    threads = blocks.map do |block|
      Thread.new do
        block.call
      rescue StandardError => e
        mutex.synchronize { errors << e }
      end
    end
    threads.each(&:join)
    errors
  end

  it 'waits for a held write lock instead of raising "database is locked"' do
    with_file_database do |db|
      hold_lock = proc do
        db.transaction do
          db[:widgets].insert
          sleep 0.3
        end
      end
      write_meanwhile = proc do
        sleep 0.1
        db[:widgets].insert
      end

      assert_empty errors_from(hold_lock, write_meanwhile)
      assert_equal 2, db[:widgets].count
    end
  end

  it 'lets a read-then-write transaction commit alongside another writer' do
    with_file_database do |db|
      # Under BEGIN DEFERRED the read takes a shared lock that the later write
      # has to upgrade, and SQLite refuses that upgrade with an immediate
      # SQLITE_BUSY no busy handler is allowed to retry.
      read_then_write = proc do
        db.transaction do
          db[:widgets].count
          sleep 0.2
          db[:widgets].insert
        end
      end
      write_meanwhile = proc do
        sleep 0.1
        db[:widgets].insert
      end

      assert_empty errors_from(read_then_write, write_meanwhile)
      assert_equal 2, db[:widgets].count
    end
  end

  it 'ships the settings these tests depend on' do
    assert_equal :immediate, DB.transaction_mode
  end
end
