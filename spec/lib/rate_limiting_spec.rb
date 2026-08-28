# frozen_string_literal: true

require_relative 'spec_helper'
require 'rack/test'
require 'rate_limiting'

describe RateLimiting do
  include Rack::Test::Methods

  before do
    # A fresh store per test so counts never leak between examples.
    RateLimiting.configure store: ThrottleStore.new
  end

  def app
    builder = Rack::Builder.new do
      use Rack::Attack
      run ->(_env) { [200, {'content-type' => 'text/plain'}, %w[ok]] }
    end
    builder.to_app
  end

  # TEST-NET-3, reserved for documentation and testing.
  def client_ip suffix = 1
    "203.0.113.#{suffix}"
  end

  def hammer path, times, method: :post, ip: client_ip
    times.times { send(method, path, {}, 'REMOTE_ADDR' => ip) }
  end

  describe 'email sending endpoints' do
    it 'allows a handful of signups' do
      hammer '/sign-up', 5

      assert_equal 200, last_response.status
    end

    it 'blocks the sixth signup within the hour' do
      hammer '/sign-up', 6

      assert_equal 429, last_response.status
    end

    it 'explains the wait rather than failing silently' do
      hammer '/sign-up', 6

      assert_includes last_response.body, 'Too many requests'
    end

    it 'sets retry-after so clients can back off' do
      hammer '/sign-up', 6

      assert_equal '3600', last_response.headers['retry-after']
    end

    it 'throttles password reset requests, which mail a third party' do
      hammer '/reset-password-request', 6

      assert_equal 429, last_response.status
    end

    it 'counts each email endpoint against the same budget' do
      hammer '/sign-up', 3
      hammer '/reset-password-request', 3

      assert_equal 429, last_response.status
    end

    it 'tracks limits per IP, not globally' do
      hammer '/sign-up', 6, ip: client_ip(1)
      post '/sign-up', {}, 'REMOTE_ADDR' => client_ip(2)

      assert_equal 200, last_response.status
    end

    it 'ignores GETs to those paths, which send no mail' do
      hammer '/sign-up', 10, method: :get

      assert_equal 200, last_response.status
    end
  end

  describe 'logins' do
    # Rodauth's lockout is per account, so it never sees stuffing spread thin.
    it 'blocks credential stuffing spread across many accounts' do
      hammer '/authenticate', 21

      assert_equal 429, last_response.status
    end

    it 'leaves a normal number of retries alone' do
      hammer '/authenticate', 20

      assert_equal 200, last_response.status
    end
  end

  describe 'search endpoints' do
    it 'throttles writes at ten a minute' do
      hammer '/search/availability', 11

      assert_equal 429, last_response.status
    end

    it 'throttles reads more loosely' do
      hammer '/search/shelves', 30, method: :get

      assert_equal 200, last_response.status
    end

    it 'blocks reads past thirty a minute' do
      hammer '/search/shelves', 31, method: :get

      assert_equal 429, last_response.status
    end
  end

  describe 'backstop' do
    it 'caps writes to any path, including ones added later' do
      hammer '/some/future/endpoint', 61

      assert_equal 429, last_response.status
    end
  end

  describe 'safelist' do
    it 'never throttles the health check Render polls' do
      hammer '/health', 200, method: :get

      assert_equal 200, last_response.status
    end

    it 'never throttles assets' do
      hammer '/assets/css/styles.css', 200, method: :get

      assert_equal 200, last_response.status
    end
  end
end
