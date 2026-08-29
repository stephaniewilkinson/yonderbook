# frozen_string_literal: true

require_relative 'spec_helper'

# An anonymous visitor's Goodreads credentials live in the Cache under their
# session id, which a Rack::Test request cannot reach -- the id is sealed in the
# encrypted session cookie. Stub the read instead, so these specs exercise the
# routes rather than the session plumbing.
ANON_CREDENTIALS = {anon_goodreads_user_id: '1', anon_goodreads_token: 'token', anon_goodreads_secret: 'secret'}.freeze

describe 'Anonymous search flow' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  # `cached` lets each spec choose how far through the flow the visitor has
  # already got, by supplying the values that step would have left behind.
  def with_anonymous_session(cached = {}, &)
    values = ANON_CREDENTIALS.merge(cached)
    Cache.stub(:get, ->(_session, key) { values[key] }) do
      Auth.stub(:rebuild_access_token, Object.new, &)
    end
  end

  describe 'GET /search-callback' do
    it 'redirects to / with error when no request token is cached' do
      visit '/search-callback'
      assert_current_path '/'
    end
  end

  describe 'GET /search/shelves' do
    it 'redirects to / when no session credentials exist' do
      visit '/search/shelves'
      assert_current_path '/'
    end
  end

  describe 'GET /search/library' do
    it 'redirects to / when no session credentials exist' do
      visit '/search/library'

      assert_current_path '/'
    end
  end

  describe 'GET /search/shelves/:name/overdrive' do
    it 'redirects to / when no session credentials exist' do
      visit '/search/shelves/to-read/overdrive'

      assert_current_path '/'
    end
  end

  # POST /search/library calls check_csrf!, but its form lives in the shared
  # shelves/overdrive.erb, which the authenticated flow also renders. The
  # authenticated POST /libraries does not check, so a missing token went
  # unnoticed there and broke every anonymous zip code submission.
  describe 'GET /search/shelves/:name/overdrive form' do
    it 'emits the CSRF token that POST /search/library demands' do
      with_anonymous_session do
        get '/search/shelves/to-read/overdrive'

        assert_includes last_response.body, '_csrf'
      end
    end

    it 'posts to the anonymous library route' do
      with_anonymous_session do
        get '/search/shelves/to-read/overdrive'

        assert_includes last_response.body, 'action="/search/library"'
      end
    end
  end

  # Someone can connect Goodreads before they have an account. Those credentials
  # live in the session cache, which dies with the session, so signing up has to
  # copy them onto the account or the connection is silently lost.
  describe 'account creation with anonymous Goodreads credentials' do
    def sign_up email
      visit '/sign-up'
      fill_in 'Email', with: email
      fill_in 'Password', with: 'SecurePassword123!'
      click_button 'Create Account'
    end

    it 'copies the session credentials onto the new account' do
      email = "migrate_#{Time.now.to_i}_#{rand(9999)}@example.com"
      with_anonymous_session { sign_up email }

      account = DB[:accounts].where(email: email).first
      refute_nil account, 'the account was not created'
      connection = DB[:goodreads_connections].where(user_id: account[:id]).first

      refute_nil connection, 'the Goodreads connection was not migrated'
      assert_equal ANON_CREDENTIALS[:anon_goodreads_user_id], connection[:goodreads_user_id]
      assert_equal ANON_CREDENTIALS[:anon_goodreads_token], connection[:access_token]
    end

    # They can always reconnect from /connections, so a failed migration must not
    # cost them the account they actually asked for.
    it 'still creates the account when the migration raises' do
      email = "migrate_fail_#{Time.now.to_i}_#{rand(9999)}@example.com"
      exploding = ->(*) { raise 'Goodreads is unreachable' }

      with_anonymous_session do
        Goodreads.stub(:save_goodreads_connection, exploding) { sign_up email }
      end

      refute_nil DB[:accounts].where(email: email).first, 'the account was not created'
    end

    it 'leaves accounts without session credentials alone' do
      email = "no_migrate_#{Time.now.to_i}_#{rand(9999)}@example.com"
      sign_up email

      account = DB[:accounts].where(email: email).first
      refute_nil account, 'the account was not created'
      assert_empty DB[:goodreads_connections].where(user_id: account[:id]).all
    end
  end

  describe 'GET /search/availability' do
    it 'redirects to / when no session credentials exist' do
      visit '/search/availability'

      assert_current_path '/'
    end

    # Resume at the furthest step already completed, matching the authenticated
    # page, rather than sending someone who picked a library back to the start.
    it 'sends a visitor who has chosen a library back to the library picker' do
      with_anonymous_session(shelf_name: 'to-read', libraries: [%w[1047 Library]]) do
        get '/search/availability'

        assert_equal '/search/library', last_response.headers['location']
      end
    end

    it 'sends a visitor who has chosen no library back to the shelf list' do
      with_anonymous_session do
        get '/search/availability'

        assert_equal '/search/shelves', last_response.headers['location']
      end
    end
  end

  describe 'POST /search/availability' do
    it 'redirects to / when no session credentials exist' do
      post '/search/availability', 'consortium' => '1047'

      assert_equal '/', last_response.headers['location']
    end

    # check_csrf! raises, and the error_handler plugin turns that into a 500, so
    # this is what rejection looks like from outside. The status is the point:
    # 404 would mean the route is missing, and a redirect would mean the POST
    # ran without a token. Roda stops the request before any Goodreads or
    # OverDrive call, which is what keeps this spec off the network.
    it 'refuses a request with no CSRF token' do
      with_anonymous_session do
        post '/search/availability', 'consortium' => '1047'

        assert_equal 500, last_response.status
      end
    end
  end
end
