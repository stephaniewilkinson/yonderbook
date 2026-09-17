# frozen_string_literal: true

require_relative 'spec_helper'

ROOT_ANON_CREDENTIALS = {anon_goodreads_user_id: '7', anon_goodreads_token: 'token', anon_goodreads_secret: 'secret'}.freeze

describe 'root route' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  # Only the cache is stubbed here. rebuild_access_token makes no HTTP call --
  # it just wraps the stored credentials in an OAuth::AccessToken -- so the
  # real one runs.
  def with_goodreads_session(&)
    Cache.stub(:get, ->(_session, key) { ROOT_ANON_CREDENTIALS[key] }, &)
  end

  describe 'GET /' do
    it 'serves the search interface to a new visitor' do
      get '/'

      assert_equal 200, last_response.status
      assert_includes last_response.body, 'href="/connect"'
    end

    # The OOM work moved r.root ahead of the session write so bot traffic stops
    # allocating a cookie per request. Serving a different view here must not
    # quietly undo that: the README names it as a primary fix.
    it 'writes no session cookie' do
      get '/'

      cookie = last_response.headers.keys.find { |key| key.casecmp('set-cookie').zero? }

      assert_nil cookie, 'the homepage wrote a session cookie'
    end

    # #1383. The same URL answers three ways depending on session state, so a
    # cached copy is a copy of someone else's answer. It was sending no
    # Cache-Control, ETag or Last-Modified at all, which lets a browser reuse
    # it under heuristic freshness -- Firefox served a logged-in visitor the
    # cached anonymous homepage without asking the server.
    it 'forbids caching, because the response depends on the session' do
      get '/'

      assert_equal 'private, no-store', last_response.headers['Cache-Control']
    end

    it 'sends a visitor who already connected Goodreads to their shelves' do
      with_goodreads_session do
        get '/'

        assert_equal '/search/shelves', last_response.headers['location']
      end
    end

    it 'sends a logged-in user to their home page' do
      email, password = create_account_direct
      password_login(email, password)
      # password_login clicks and returns without waiting for the POST to land.
      # Visiting '/' before the session cookie is set intermittently saw the
      # anonymous homepage instead of the redirect. seed_goodreads_user waits
      # on the same text for the same reason.
      assert_text 'Welcome back,'

      visit '/'

      assert_current_path '/home'
    end
  end

  describe 'GET /connect' do
    it 'redirects to the Goodreads authorize url' do
      # Stubbed at the HTTP layer, so the OAuth signing and the authorize_url
      # the oauth gem derives from the token both run for real.
      stub_request(:post, HttpFixtures::REQUEST_TOKEN_URL).to_return(status: 200, body: 'oauth_token=abc&oauth_token_secret=xyz')

      get '/connect'

      assert_equal 'https://www.goodreads.com/oauth/authorize?oauth_token=abc', last_response.headers['location']
    end

    # fetch_and_cache_request_token swallows the failure and returns nil, so
    # without a fallback this would redirect to nowhere.
    it 'sends the visitor back to the homepage when Goodreads is unreachable' do
      stub_request(:post, HttpFixtures::REQUEST_TOKEN_URL).to_timeout

      get '/connect'

      assert_equal '/', last_response.headers['location']
    end

    it 'retries a timeout before giving up' do
      # Auth.fetch_request_token retries twice on a network error, which is
      # three attempts in total. Nothing proved that until the request could
      # be counted.
      stub_request(:post, HttpFixtures::REQUEST_TOKEN_URL).to_timeout

      get '/connect'

      assert_requested(:post, HttpFixtures::REQUEST_TOKEN_URL, times: 3)
    end
  end
end
