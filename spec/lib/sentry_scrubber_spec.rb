# frozen_string_literal: true

require_relative 'spec_helper'
require 'sentry-ruby'
require 'sentry_scrubber'

describe SentryScrubber do
  # Stand-ins for Sentry::ErrorEvent and Sentry::RequestInterface with the
  # attributes before_send touches.
  FakeEvent = Struct.new(:request, :extra, :contexts, :tags)
  FakeRequest = Struct.new(:data, :cookies, :query_string, :env, :headers, :url, :http_method)

  def scrub **attrs
    SentryScrubber.call FakeEvent.new(attrs[:request], attrs.fetch(:extra, {}), attrs.fetch(:contexts, {}), attrs.fetch(:tags, {}))
  end

  it 'returns the event so it is still sent' do
    event = FakeEvent.new(nil, {}, {}, {})
    assert_same event, SentryScrubber.call(event, nil)
  end

  it 'tolerates an event with no request attached, which is every event today' do
    assert_nil scrub.request
  end

  describe 'request data' do
    # The BookMooch import posts a username and password, and Rodauth's login
    # and account-creation forms post credentials. No allowlist of body keys is
    # safe on those routes, so the body goes wholesale.
    it 'drops the body, cookies, query string and env' do
      body = {'username' => 'steph', 'password' => 'hunter2'}
      request = FakeRequest.new(body, 'rack.session=abc123', 'token=xyz', {'HTTP_COOKIE' => 'rack.session=abc123'}, {})

      result = scrub(request: request).request

      assert_nil result.data
      assert_nil result.cookies
      assert_nil result.query_string
      assert_empty result.env
    end

    it 'keeps the url and method, which name the failing route' do
      request = FakeRequest.new(nil, nil, nil, {}, {}, 'https://yonderbook.com/goodreads/shelves', 'GET')

      result = scrub(request: request).request

      assert_equal 'https://yonderbook.com/goodreads/shelves', result.url
      assert_equal 'GET', result.http_method
    end

    it 'redacts credential-carrying headers' do
      request = FakeRequest.new(nil, nil, nil, {}, {'Authorization' => 'Bearer abc', 'Content-Type' => 'application/json'}, nil, nil)

      headers = scrub(request: request).request.headers

      assert_equal SentryScrubber::REDACTED, headers['Authorization']
      assert_equal 'application/json', headers['Content-Type']
    end
  end

  describe 'hand-set event data' do
    it 'redacts sensitive keys in extra' do
      extra = scrub(extra: {session_id: 'abc123', book_count: 42}).extra

      assert_equal SentryScrubber::REDACTED, extra[:session_id]
      assert_equal 42, extra[:book_count]
    end

    it 'redacts nested values' do
      contexts = scrub(contexts: {goodreads: {user_id: '123', oauth_token: 'secret'}}).contexts

      assert_equal '123', contexts[:goodreads][:user_id]
      assert_equal SentryScrubber::REDACTED, contexts[:goodreads][:oauth_token]
    end

    it 'redacts inside arrays' do
      extra = scrub(extra: {attempts: [{password: 'hunter2'}, {password: 'hunter3'}]}).extra

      assert_equal [{password: SentryScrubber::REDACTED}, {password: SentryScrubber::REDACTED}], extra[:attempts]
    end

    it 'leaves the param-key list enrich_sentry_error sends alone' do
      # route_helpers sends request.params.keys, not request.params. The key
      # names are the point, so a key named "password" stays visible as a name.
      contexts = scrub(contexts: {request: {method: 'POST', path: '/login', params: %w[login password]}}).contexts

      assert_equal %w[login password], contexts[:request][:params]
    end

    it 'redacts sensitive tags' do
      assert_equal SentryScrubber::REDACTED, scrub(tags: {route: '/login', 'api-key' => 'abc'}).tags['api-key']
    end
  end
end
