# frozen_string_literal: true

require_relative 'spec_helper'
require 'request_timeout'

describe RequestTimeout do
  def build_app response_time: 0
    inner_app = ->(_env) do
      sleep(response_time)
      [200, {}, %w[OK]]
    end
    RequestTimeout.new(inner_app, timeout: 0.5)
  end

  it 'passes through when no async task is running' do
    app = build_app
    status, = app.call({'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/'})
    assert_equal 200, status
  end

  it 'skips timeout for websocket upgrades' do
    app = build_app
    env = {'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/ws/test', 'HTTP_UPGRADE' => 'websocket'}
    status, = app.call(env)
    assert_equal 200, status
  end

  it 'includes route in error message' do
    error = RequestTimeout::Error.new('GET /slow exceeded 25s timeout')
    assert_includes error.message, 'GET /slow'
  end
end
