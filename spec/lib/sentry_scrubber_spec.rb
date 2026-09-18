# frozen_string_literal: true

require_relative 'spec_helper'
require 'secrets'
require 'sentry-ruby'
require 'sentry_scrubber'

describe SentryScrubber do
  # Stand-ins for Sentry::ErrorEvent and Sentry::RequestInterface with the
  # attributes before_send touches.
  FakeSentryEvent = Struct.new(:request, :extra, :contexts, :tags)
  FakeSentryRequest = Struct.new(:data, :cookies, :query_string, :env, :headers, :url, :http_method)

  def scrub **attrs
    SentryScrubber.call FakeSentryEvent.new(attrs[:request], attrs.fetch(:extra, {}), attrs.fetch(:contexts, {}), attrs.fetch(:tags, {}))
  end

  it 'returns the event so it is still sent' do
    event = FakeSentryEvent.new(nil, {}, {}, {})
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
      request = FakeSentryRequest.new(body, 'rack.session=abc123', 'token=xyz', {'HTTP_COOKIE' => 'rack.session=abc123'}, {})

      result = scrub(request: request).request

      assert_nil result.data
      assert_nil result.cookies
      assert_nil result.query_string
      assert_empty result.env
    end

    it 'keeps the url and method, which name the failing route' do
      request = FakeSentryRequest.new(nil, nil, nil, {}, {}, 'https://yonderbook.com/goodreads/shelves', 'GET')

      result = scrub(request: request).request

      assert_equal 'https://yonderbook.com/goodreads/shelves', result.url
      assert_equal 'GET', result.http_method
    end

    it 'redacts credential-carrying headers' do
      request = FakeSentryRequest.new(nil, nil, nil, {}, {'Authorization' => 'Bearer abc', 'Content-Type' => 'application/json'}, nil, nil)

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

  # Key-name scrubbing cannot reach free text, and the Goodreads key travels as
  # a query parameter -- so an exception raised mid-request carries it in the
  # message, which used to go to Sentry verbatim.
  describe 'credential values in free text' do
    FakeSingleException = Struct.new(:value)
    # `values` shadows Struct#values, which is exactly the shape
    # Sentry::ExceptionInterface has, so the fake matches it.
    FakeExceptionInterface = Struct.new(:values)

    def with_key key
      previous = ENV.fetch('GOODREADS_API_KEY', nil)
      ENV['GOODREADS_API_KEY'] = key
      Secrets.reset!
      yield
    ensure
      previous.nil? ? ENV.delete('GOODREADS_API_KEY') : ENV['GOODREADS_API_KEY'] = previous
      Secrets.reset!
    end

    def event_with_exception message
      event = FakeSentryEvent.new(nil, {}, {}, {})
      event.define_singleton_method(:exception) { @exception ||= FakeExceptionInterface.new([FakeSingleException.new(message)]) }
      event.define_singleton_method(:breadcrumbs) { nil }
      event
    end

    it 'redacts the key out of an exception message' do
      with_key 'abcd1234efgh5678' do
        event = event_with_exception('Timeout on https://www.goodreads.com/review/list/42.xml?key=abcd1234efgh5678&v=2')

        SentryScrubber.call event

        refute_includes event.exception.values.first.value, 'abcd1234efgh5678'
      end
    end

    it 'redacts the key out of a value nested in extra' do
      with_key 'abcd1234efgh5678' do
        scrubbed = scrub(extra: {last_url: 'https://www.goodreads.com/shelf/list.xml?key=abcd1234efgh5678'})

        refute_includes scrubbed.extra[:last_url], 'abcd1234efgh5678'
      end
    end

    it 'leaves an unrelated message intact' do
      with_key 'abcd1234efgh5678' do
        event = event_with_exception('Net::ReadTimeout')

        SentryScrubber.call event

        assert_equal 'Net::ReadTimeout', event.exception.values.first.value
      end
    end
  end
end
