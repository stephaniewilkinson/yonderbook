# frozen_string_literal: true

require_relative 'spec_helper'
require 'sentry-ruby'
require 'sentry_tracing'

describe SentryTracing do
  # Stands in for Sentry::Transaction, which needs a configured hub.
  class FakeTransaction
    attr_reader :name, :op, :http_status

    def initialize name, operation
      @name = name
      @op = operation
      @finished = false
    end

    # Named for Sentry::Transaction's own API, which this stands in for.
    def set_http_status status
      @http_status = status
    end

    def finish
      @finished = true
    end

    def finished? = @finished
  end

  def tracing
    started = []
    stub = ->(name:, op:) { FakeTransaction.new(name, op).tap { |t| started << t } }
    Sentry.stub(:start_transaction, stub) { yield started }
  end

  def get path, app = ->(_env) { [200, {}, %w[OK]] }
    SentryTracing.new(app).call({'REQUEST_METHOD' => 'GET', 'PATH_INFO' => path})
  end

  it 'starts no transaction for untraced routes' do
    tracing do |started|
      %w[/ /about /health /login /assets/styles.css /libraries].each { |path| get path }
      assert_empty started
    end
  end

  it 'skips the endpoints the browser polls while a background job runs' do
    tracing do |started|
      get '/goodreads/availability/progress'
      get '/goodreads/shelves/to-read/bookmooch/progress'
      get '/goodreads/shelves/to-read/bookmooch/results'
      assert_empty started
    end
  end

  it 'traces the route families with uncontrolled network calls behind them' do
    tracing do |started|
      get '/goodreads/shelves'
      get '/goodreads/shelves/to-read/overdrive'
      get '/goodreads/availability'

      assert_equal ['GET /goodreads/shelves', 'GET /goodreads/shelves/:shelf/overdrive', 'GET /goodreads/availability'], started.map(&:name)
      assert_equal %w[http.server http.server http.server], started.map(&:op)
    end
  end

  it 'normalizes the shelf name so a shelf is not its own transaction' do
    tracing do |started|
      get '/goodreads/shelves/currently-reading'
      get '/goodreads/shelves/sci-fi-owned'

      assert_equal ['GET /goodreads/shelves/:shelf'], started.map(&:name).uniq
    end
  end

  it 'records the status and finishes the transaction' do
    tracing do |started|
      get '/goodreads/shelves', ->(_env) { [302, {}, []] }

      assert_equal 302, started.first.http_status
      assert_predicate started.first, :finished?
    end
  end

  it 'finishes the transaction when the route raises' do
    tracing do |started|
      assert_raises(RuntimeError) { get '/goodreads/shelves', ->(_env) { raise 'boom' } }
      assert_predicate started.first, :finished?
    end
  end

  it 'serves the route when tracing is off' do
    Sentry.stub(:start_transaction, ->(**) { }) do
      status, = get '/goodreads/shelves'
      assert_equal 200, status
    end
  end
end
