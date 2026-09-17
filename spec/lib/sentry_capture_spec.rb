# frozen_string_literal: true

require_relative 'spec_helper'
require 'async'
require 'sentry-ruby'
require 'sentry_capture'

describe SentryCapture do
  # Sentry.init is not called in specs, so capture_exception is a no-op. Record
  # the calls instead of asserting on a transport.
  def capturing
    captured = []
    Sentry.stub(:capture_exception, ->(e, **) { captured << e }) { yield captured }
  end

  def build_app &raiser
    SentryCapture.new(raiser || ->(_env) { [200, {}, %w[OK]] })
  end

  it 'passes a successful response through untouched' do
    capturing do |captured|
      status, _headers, body = build_app.call({})
      assert_equal 200, status
      assert_equal %w[OK], body
      assert_empty captured
    end
  end

  it 'captures and re-raises what the middleware above it raises' do
    error = ArgumentError.new('bad throttle discriminator')
    app = build_app { |_env| raise error }

    capturing do |captured|
      assert_raises(ArgumentError) { app.call({}) }
      assert_equal [error], captured
    end
  end

  it 'captures exceptions outside StandardError' do
    app = build_app { |_env| raise NoMemoryError, 'failed to allocate' }

    capturing do |captured|
      assert_raises(NoMemoryError) { app.call({}) }
      assert_equal 1, captured.size
    end
  end

  it 'stays quiet for shutdown and task cancellation' do
    [SystemExit.new, SignalException.new('TERM'), Async::Stop.new].each do |error|
      app = build_app { |_env| raise error }

      capturing do |captured|
        assert_raises(error.class) { app.call({}) }
        assert_empty captured, "#{error.class} should not open an issue"
      end
    end
  end

  describe '.capture_once' do
    it 'reports an exception the first time only' do
      error = RuntimeError.new('boom')

      capturing do |captured|
        SentryCapture.capture_once error
        SentryCapture.capture_once error
        assert_equal [error], captured
      end
    end

    it 'does not report again from the middleware after the route rescue did' do
      # Outside production the route-block rescue in app.rb captures and then
      # re-raises, so error_handler and this middleware see the same object.
      error = RuntimeError.new('raised inside the route tree')
      app = build_app { |_env| raise error }

      capturing do |captured|
        SentryCapture.capture_once error
        assert_raises(RuntimeError) { app.call({}) }
        assert_equal 1, captured.size
      end
    end

    it 'passes extra context through' do
      options = []
      Sentry.stub(:capture_exception, ->(_e, **opts) { options << opts }) do
        SentryCapture.capture_once RuntimeError.new('boom'), extra: {isbn: '9780062316097'}
      end
      assert_equal [{extra: {isbn: '9780062316097'}}], options
    end
  end
end
