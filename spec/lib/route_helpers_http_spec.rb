# frozen_string_literal: true

require_relative 'spec_helper'
require 'auth'
require 'cache'
require 'overdrive'
require 'route_helpers'
require 'securerandom'

# The two RouteHelpers methods that exist to turn a third party's failure into
# something a user can act on. Both were previously reachable only by stubbing
# out the very call whose failure they handle.
describe 'RouteHelpers over HTTP' do
  FIND_LIBRARIES = %r{\Ahttps://www\.overdrive\.com/mapbox/find-libraries-by-query}
  REQUEST_TOKEN = 'https://www.goodreads.com/oauth/request_token'

  # Stands in for the Roda app context: session, flash, and a request object
  # that records where it was told to redirect instead of throwing.
  let(:helper) do
    klass = Class.new do
      include RouteHelpers

      attr_accessor :session

      def flash = @flash ||= {}
    end
    obj = klass.new
    obj.session = {'session_id' => "test_#{SecureRandom.hex(8)}"}
    obj
  end

  # Records where the route would have sent the user, instead of throwing the
  # way Roda's real request object does.
  class FakeRequest
    attr_reader :redirected_to

    def redirect path = nil
      @redirected_to = path
    end
  end

  let(:request) { FakeRequest.new }

  describe '#fetch_local_libraries' do
    it 'returns the libraries when OverDrive answers' do
      stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: JSON.dump([HttpFixtures.overdrive_library]))

      libraries = helper.fetch_local_libraries(request, '98101')

      assert_equal 'Seattle Public Library', libraries.first[1]
      assert_nil request.redirected_to
    end

    it 'strips spaces out of the zip code before asking' do
      stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: '[]')

      helper.fetch_local_libraries(request, '98 101')

      assert_requested(:get, /query=98101/, times: 1)
    end

    it 'redirects with a message the user can act on when OverDrive 403s' do
      # OverDrive blocks some networks outright. The point of the rescue is
      # that this reads as "try again later", not as a bare 500.
      stub_request(:get, FIND_LIBRARIES).to_return(status: 403, body: '<html>Access Denied</html>')

      helper.fetch_local_libraries(request, '98101', fallback: '/search/library')

      assert_equal '/search/library', request.redirected_to
      assert_includes helper.flash[:error], 'could not reach OverDrive'
    end

    it 'falls back to the shelf list when no fallback path is given' do
      stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: '<html>Just a moment</html>')

      helper.fetch_local_libraries(request, '98101')

      assert_equal '/goodreads/shelves', request.redirected_to
    end
  end

  describe '#fetch_and_cache_request_token' do
    it 'returns the token and caches it' do
      stub_request(:post, REQUEST_TOKEN).to_return(status: 200, body: 'oauth_token=tok-abc&oauth_token_secret=sec-xyz')

      token = helper.fetch_and_cache_request_token

      assert_equal 'tok-abc', token.token
      assert_equal 'tok-abc', Cache.get(helper.session, :request_token).token
    end

    it 'returns the cached token without asking Goodreads twice' do
      stub_request(:post, REQUEST_TOKEN).to_return(status: 200, body: 'oauth_token=tok-abc&oauth_token_secret=sec-xyz')

      helper.fetch_and_cache_request_token
      helper.fetch_and_cache_request_token

      assert_requested(:post, REQUEST_TOKEN, times: 1)
    end

    it 'returns nil rather than raising when Goodreads answers 500' do
      # The connect page renders without the button in this case; it must not
      # take the whole page down. Auth.fetch_request_token retries first.
      stub_request(:post, REQUEST_TOKEN).to_return(status: 500, body: 'upstream error')

      assert_nil helper.fetch_and_cache_request_token
    end
  end
end
