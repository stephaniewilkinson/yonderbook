# frozen_string_literal: true

require_relative 'spec_helper'
require 'cache'
require 'json'
require 'overdrive'
require 'websockets'

# Records what a WebSocket handler wrote, so the handler can be exercised
# without a socket.
class FakeConnection
  attr_reader :messages

  def initialize
    @messages = []
    @closed = false
  end

  def write(payload) = @messages << JSON.parse(payload)

  def flush = nil

  def close = @closed = true

  def closed? = @closed

  def types = @messages.map { |m| m['type'] }
end

describe 'availability job' do
  describe 'Cache session-id accessors' do
    # set_by_id round trips through JSON on disk, which would turn the titles
    # into bare hashes. The availability view calls methods on them.
    it 'keeps objects intact, unlike the filesystem cache' do
      title = Struct.new(:copies_available).new(3)
      Cache.set_in_session 'session-objects', titles: [title]

      assert_equal 3, Cache.get_in_session('session-objects', :titles).first.copies_available
    end

    it 'reads back what the session-keyed writer stored' do
      Cache.set_in_session 'session-shared', availability_consortium: 1047

      assert_equal 1047, Cache.get_in_session('session-shared', :availability_consortium)
    end
  end

  describe 'Websockets.handle_availability' do
    it 'reports missing parameters instead of hanging the page' do
      connection = FakeConnection.new
      Websockets.handle_availability connection, 'session-with-nothing-cached'

      assert_equal %w[connected error], connection.types
      assert_equal 'Missing job parameters', connection.messages.last['message']
      assert connection.closed?, 'the socket was left open'
    end

    # The page shows a spinner until the socket says otherwise, so a crash that
    # writes nothing would spin forever.
    it 'reports an OverDrive failure rather than leaving the page spinning' do
      Cache.set_in_session 'session-overdrive-down', availability_book_info: [{title: 'A'}], availability_consortium: 1047
      connection = FakeConnection.new

      Overdrive.stub(:new, ->(*) { raise 'OverDrive is unreachable' }) do
        Websockets.handle_availability connection, 'session-overdrive-down'
      end

      assert_equal 'error', connection.types.last
      assert_includes connection.messages.last['message'], 'OverDrive'
      assert connection.closed?, 'the socket was left open'
    end
  end

  describe 'Overdrive#fetch_titles_availability progress' do
    # Skips initialize, which reaches OverDrive for a token before it does
    # anything else.
    def overdrive_over books
      overdrive = Overdrive.allocate
      overdrive.instance_variable_set :@book_info, books
      overdrive.instance_variable_set :@timings, {}
      overdrive.define_singleton_method(:process_chunk) { |_chunk, _num, _count| [] }
      overdrive
    end

    it 'reports once per chunk, ending at the chunk count' do
      chunks = 3
      overdrive = overdrive_over Array.new(chunks * Overdrive::CHUNK_SIZE) { |i| {title: "Book #{i}"} }

      updates = []
      overdrive.fetch_titles_availability { |update| updates << update }

      assert_equal chunks, updates.size
      assert_equal((1..chunks).to_a, updates.map { |u| u[:current] })
      assert(updates.all? { |u| u[:total] == chunks }, 'every update should carry the chunk count')
    end

    it 'still returns results when the callback raises' do
      overdrive = overdrive_over [{title: 'Only book'}]

      results = overdrive.fetch_titles_availability { raise IOError, 'browser went away' }

      assert_empty results
    end

    it 'works with no callback at all' do
      overdrive = overdrive_over [{title: 'Only book'}]

      assert_empty overdrive.fetch_titles_availability
    end
  end
end
