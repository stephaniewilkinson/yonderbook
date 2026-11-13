# frozen_string_literal: true

require_relative 'spec_helper'

# YONDERBOOK-38: a POST /import carrying the file but no _csrf field raised
# RouteCsrf::InvalidToken, which error_handler turned into a 500 and a Sentry
# issue. A missing or stale token is the client's problem; it gets sent back to
# the form with a message, and nothing behind the check runs.
describe 'A failed CSRF check' do
  include Rack::Test::Methods

  let(:app) { App }

  def upload
    Rack::Test::UploadedFile.new File.expand_path('../fixtures/goodreads_export.csv', __dir__), 'text/csv'
  end

  it 'sends an import with no token back to the form instead of a 500' do
    post '/import', {'library' => upload}, 'HTTP_REFERER' => 'http://example.org/import'

    assert_equal 302, last_response.status
    assert_equal '/import', last_response.headers['location']
    follow_redirect!

    assert_includes last_response.body, 'Your session has expired'
    refute_includes last_response.body, 'Imported'
  end

  # A successful import redirects too, so the status alone would pass with the
  # check switched off. The flash and the missing "Imported" notice are what
  # show the request was refused.
  def assert_refused
    follow_redirect!

    assert_includes last_response.body, 'Your session has expired'
    refute_includes last_response.body, 'Imported'
    refute_includes last_response.body, 'has been removed'
  end

  it 'rejects a token that does not decode' do
    post '/import', {'library' => upload, '_csrf' => 'not-a-token'}, 'HTTP_REFERER' => 'http://example.org/import'

    assert_equal 302, last_response.status
    assert_refused
  end

  # /import/clear has no GET route, so redirecting to the request path would 404.
  it 'returns to the page the form was on, not the POST path' do
    post '/import/clear', {}, 'HTTP_REFERER' => 'http://example.org/import'

    assert_equal '/import', last_response.headers['location']
    assert_refused
  end

  # Rodauth calls check_csrf! itself; it used to be the only caller with a rescue
  # of its own, and now relies on the plugin's failure block like the rest.
  it 'covers the Rodauth routes too' do
    post '/authenticate', {'email' => 'a@example.com', 'password' => 'x'}, 'HTTP_REFERER' => 'http://example.org/authenticate'

    assert_equal 302, last_response.status
    assert_equal '/authenticate', last_response.headers['location']
    follow_redirect!

    assert_includes last_response.body, 'Your session has expired'
  end

  it 'falls back to the home page without a usable Referer' do
    post '/import'

    assert_equal '/', last_response.headers['location']

    post '/import', {}, 'HTTP_REFERER' => 'https://evil.example.com/import'

    assert_equal '/', last_response.headers['location']
  end
end
