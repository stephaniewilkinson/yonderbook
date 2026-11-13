# frozen_string_literal: true

require_relative 'spec_helper'

# #1436: these three POST handlers ran without a CSRF check. Each spec posts
# without a token and asserts both halves: the CSRF failure message, and the
# absence of what the handler would have done had it run. A 302 alone would
# prove nothing, since every one of these handlers redirects on its own.
describe 'CSRF checks on the logged-in Goodreads routes' do
  include Rack::Test::Methods

  let(:app) { App }

  # Signs in through the real login form, token and all, so the session cookie
  # rack-test keeps afterwards is an ordinary logged-in one.
  def log_in_with_goodreads
    email, password = create_account_direct
    account = DB[:accounts].where(email: email).first
    add_goodreads_connection account[:id], '12345', 'token', 'secret'

    get '/authenticate'
    csrf = last_response.body[/id="password-login-form".*?name="_csrf" value="([^"]+)"/m, 1]
    post '/authenticate', 'email' => email, 'password' => password, '_csrf' => csrf

    refute_equal '/authenticate', last_response.headers['location'], 'login failed'
  end

  def assert_refused_back_to path, not_shown:
    assert_equal 302, last_response.status
    assert_equal path, last_response.headers['location']
    follow_redirect!

    assert_includes last_response.body, 'Your session has expired'
    refute_includes last_response.body, not_shown
  end

  before { log_in_with_goodreads }

  it 'checks POST /goodreads/shelves/:id/bookmooch' do
    post '/goodreads/shelves/to-read/bookmooch',
         {'username' => 'u', 'password' => 'p'},
         'HTTP_REFERER' => 'http://example.org/goodreads/shelves/to-read/bookmooch'

    # Without the check, the handler finds no cached shelf and sends them to
    # reload it with this message instead.
    assert_refused_back_to '/goodreads/shelves/to-read/bookmooch', not_shown: 'Your shelf needed reloading'
  end

  it 'checks POST /goodreads/shelves/:id/overdrive' do
    # The form lives on /libraries, but with nothing cached that page bounces
    # on again and spends the flash, so this comes from a page that renders.
    post '/goodreads/shelves/to-read/overdrive', {}, 'HTTP_REFERER' => 'http://example.org/home'

    assert_refused_back_to '/home', not_shown: 'Please choose at least one library'
  end

  it 'checks POST /libraries' do
    post '/libraries', {'zipcode' => ''}, 'HTTP_REFERER' => 'http://example.org/goodreads/shelves/to-read/overdrive'

    assert_refused_back_to '/goodreads/shelves/to-read/overdrive', not_shown: 'You need to enter a zip code'
  end
end
