# frozen_string_literal: true

require_relative 'http_mocking'

# Default stubs for every third party the app can reach, registered before each
# spec in spec/web.
#
# The browser specs drive whole flows, so a single page load can touch Goodreads
# OAuth, a shelf list and an OverDrive lookup. Requiring each spec to stub all
# of that would bury the thing the spec is actually about, and leaving them
# unstubbed makes the page 500 -- WebMock::NetConnectNotAllowedError descends
# from Exception, so the `rescue StandardError` guards in lib/route_helpers.rb
# that normally degrade gracefully cannot catch it.
#
# So: every service answers plausibly by default, and a spec that cares about a
# particular response calls stub_request itself. A later stub for the same URL
# wins, which is what makes the override work.
#
# This is also what makes the Goodreads-backed specs runnable without
# credentials. They used to need a live GOODREADS_API_KEY and a real shelf on a
# real account.
module DefaultExternalApis
  # Shelf names the browser specs navigate to by name: 'abandoned' and 'zora'
  # are hard-coded in spec/web/system_spec.rb, and 'to-read' is the default
  # everywhere else. Keep them here or those specs cannot find their links.
  SHELVES = [['to-read', 12], ['read', 40], ['currently-reading', 3], ['abandoned', 4], ['zora', 5]].freeze

  def before_setup
    super
    stub_goodreads
    stub_overdrive
    stub_bookmooch
    stub_open_library
  end

  # webmock/minitest installs its reset by aliasing Minitest::Test#teardown.
  # Minitest::Capybara::Behaviour defines its own #teardown and is included into
  # the describe class, so it takes precedence over the superclass alias and
  # the reset never runs -- stubs and request counts then leak between specs,
  # which is how an assert_requested(times: 3) first read 7.
  #
  # after_teardown is a lifecycle hook rather than a method anything overrides,
  # and this module is prepended, so this runs whatever else is in play.
  def after_teardown
    WebMock.reset!
    super
  end

  private

  def stub_goodreads
    stub_request(:post, 'https://www.goodreads.com/oauth/request_token')
      .to_return(status: 200, body: 'oauth_token=default-request-token&oauth_token_secret=default-request-secret')
    stub_request(:post, 'https://www.goodreads.com/oauth/access_token')
      .to_return(status: 200, body: 'oauth_token=default-access-token&oauth_token_secret=default-access-secret')
    stub_request(:get, %r{\Ahttps://www\.goodreads\.com/shelf/list\.xml}).to_return(status: 200, body: HttpFixtures.goodreads_shelf_list(SHELVES))
    stub_request(:get, %r{\Ahttps://www\.goodreads\.com/review/list/})
      .to_return(status: 200, body: HttpFixtures.goodreads_review_page([HttpFixtures.goodreads_review]))
  end

  def stub_overdrive
    stub_request(:get, %r{\Ahttps://www\.overdrive\.com/mapbox/find-libraries-by-query})
      .to_return(status: 200, body: JSON.dump([HttpFixtures.overdrive_library]))
    stub_request(:post, 'https://oauth.overdrive.com/token')
      .to_return(status: 200, body: JSON.dump({'access_token' => 'default-overdrive-token', 'expires_in' => 3600}))
    # No collection means no titles, which every availability view renders as an
    # empty result rather than an error.
    stub_request(:get, %r{\Ahttps://api\.overdrive\.com/})
      .to_return(status: 200, body: JSON.dump({'collectionToken' => 'default-collection', 'products' => [], 'availability' => []}))
  end

  def stub_bookmooch
    stub_request(:head, 'https://api.bookmooch.com').to_return(status: 200)
    stub_request(:any, %r{\Ahttps://api\.bookmooch\.com/}).to_return(status: 200, body: '<?xml version="1.0" encoding="UTF-8"?><userids></userids>')
  end

  def stub_open_library
    stub_request(:get, %r{\Ahttps://openlibrary\.org/}).to_return(status: 200, body: JSON.dump({'entries' => [], 'docs' => []}))
  end
end
