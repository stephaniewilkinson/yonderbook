# frozen_string_literal: true

require_relative 'spec_helper'

ROOT_ANON_CREDENTIALS = {anon_goodreads_user_id: '7', anon_goodreads_token: 'token', anon_goodreads_secret: 'secret'}.freeze

describe 'root route' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  def with_goodreads_session(&)
    Cache.stub(:get, ->(_session, key) { ROOT_ANON_CREDENTIALS[key] }) do
      Auth.stub(:rebuild_access_token, Object.new, &)
    end
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

    it 'sends a visitor who already connected Goodreads to their shelves' do
      with_goodreads_session do
        get '/'

        assert_equal '/search/shelves', last_response.headers['location']
      end
    end

    it 'sends a logged-in user to their home page' do
      email, password = create_account_direct
      password_login(email, password)
      visit '/'

      assert_current_path '/home'
    end
  end

  describe 'GET /connect' do
    it 'redirects to the Goodreads authorize url' do
      token = Struct.new(:authorize_url).new('https://www.goodreads.com/oauth/authorize?oauth_token=abc')

      Auth.stub(:fetch_request_token, token) do
        get '/connect'

        assert_equal token.authorize_url, last_response.headers['location']
      end
    end

    # fetch_and_cache_request_token swallows the failure and returns nil, so
    # without a fallback this would redirect to nowhere.
    it 'sends the visitor back to the homepage when Goodreads is unreachable' do
      Auth.stub(:fetch_request_token, ->(*) { raise 'Goodreads is unreachable' }) do
        get '/connect'

        assert_equal '/', last_response.headers['location']
      end
    end
  end
end
