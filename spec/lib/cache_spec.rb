# frozen_string_literal: true

require_relative 'spec_helper'
require 'cache'
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
end
