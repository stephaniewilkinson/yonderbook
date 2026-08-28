# frozen_string_literal: true

require_relative 'spec_helper'
require 'throttle_store'

describe ThrottleStore do
  let(:store) { ThrottleStore.new }

  describe '#increment' do
    it 'returns the running count' do
      store.increment 'k', 1, expires_in: 60

      assert_equal 2, store.increment('k', 1, expires_in: 60)
    end

    it 'starts from zero for an unseen key' do
      assert_equal 1, store.increment('fresh', 1, expires_in: 60)
    end

    it 'restarts the count once the window has passed' do
      store.increment 'k', 1, expires_in: 0

      assert_equal 1, store.increment('k', 1, expires_in: 60)
    end

    it 'keeps separate keys separate' do
      store.increment 'a', 1, expires_in: 60

      assert_equal 1, store.increment('b', 1, expires_in: 60)
    end
  end

  describe '#read' do
    it 'returns what was written' do
      store.write 'k', 7, expires_in: 60

      assert_equal 7, store.read('k')
    end

    it 'returns nil for an unknown key' do
      assert_nil store.read('nope')
    end

    it 'returns nil once the entry has expired' do
      store.write 'k', 7, expires_in: 0

      assert_nil store.read('k')
    end

    it 'keeps entries with no expiry' do
      store.write 'k', 7

      assert_equal 7, store.read('k')
    end
  end

  describe '#delete and #delete_matched' do
    it 'removes a single key' do
      store.write 'k', 1, expires_in: 60
      store.delete 'k'

      assert_nil store.read('k')
    end

    it 'removes every key under a prefix, as Rack::Attack.reset! expects' do
      store.write 'rack::attack:a', 1, expires_in: 60
      store.write 'rack::attack:b', 1, expires_in: 60
      store.delete_matched 'rack::attack*'

      assert_equal 0, store.size
    end

    it 'leaves keys outside the prefix alone' do
      store.write 'rack::attack:a', 1, expires_in: 60
      store.write 'other', 1, expires_in: 60
      store.delete_matched 'rack::attack*'

      assert_equal 1, store.size
    end
  end

  # The reason this store exists rather than a plain Hash: an attacker cycling
  # through IPs must not be able to grow it without bound on a 512MB box.
  describe 'pruning' do
    it 'reclaims expired entries instead of growing forever' do
      (ThrottleStore::PRUNE_EVERY + 1).times { |i| store.write "key-#{i}", 1, expires_in: 0 }

      assert_operator store.size, :<, 10
    end

    it 'does not discard entries that are still live' do
      store.write 'keeper', 1, expires_in: 300
      ThrottleStore::PRUNE_EVERY.times { |i| store.write "junk-#{i}", 1, expires_in: 0 }

      assert_equal 1, store.read('keeper')
    end
  end

  describe 'thread safety' do
    # Falcon serves this app with a threaded container, so counters are shared
    # across threads and a lost update would silently weaken every limit.
    it 'does not lose increments under concurrency' do
      threads = Array.new(10) { Thread.new { 100.times { store.increment 'shared', 1, expires_in: 60 } } }
      threads.each(&:join)

      assert_equal 1000, store.read('shared')
    end
  end
end
