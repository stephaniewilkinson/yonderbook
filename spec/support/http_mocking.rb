# frozen_string_literal: true

require 'vcr'
require 'webmock/minitest'

# HTTP-level mocking for the four external services this app talks to.
#
# Stubbing at the module boundary (Goodreads.stub, Auth.stub) keeps the suite
# offline but skips the HTTP layer, the response parsers and the error handling
# -- which is where breakage against a third party actually lands. These stubs
# sit under all of that instead.
#
# Almost every call goes through Async::HTTP, not Net::HTTP, in three shapes:
#
#   Async::HTTP::Internet.get       goodreads.rb, alternate_isbns.rb
#   Async::HTTP::Internet.new       bookmooch.rb, overdrive.rb, library_search.rb
#   Async::HTTP::Client.new         goodreads.rb, bookmooch.rb, overdrive.rb
#
# WebMock's async_http_client adapter swaps the Async::HTTP::Client constant,
# and Internet#make_client resolves that constant at call time, so one swap
# covers all three. The oauth gem (lib/auth.rb) and resend (lib/email.rb, via
# HTTParty) use Net::HTTP and are covered by the adapter for that.
#
# Two things to know when writing a stub:
#
# - Async::HTTP::Internet adds `Accept-Encoding: gzip, identity`. It does not
#   affect a plain stub_request(:get, url), but a stub using .with(headers:)
#   must include it or it will never match.
# - Register stubs before the reactor runs. Registering inside an Async block
#   that has already started is a race.
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path('../fixtures/cassettes', __dir__)
  config.hook_into :webmock
  # :once records when a cassette is missing and replays when it exists, so a
  # run with real credentials fills in a gap and every run after that is
  # offline. Delete the file to re-record.
  config.default_cassette_options = {record: :once}

  # Nothing recorded should carry a credential. The placeholders are what ends
  # up in the committed YAML.
  config.filter_sensitive_data('<GOODREADS_API_KEY>') { ENV.fetch('GOODREADS_API_KEY', nil) }
  config.filter_sensitive_data('<GOODREADS_SECRET>') { ENV.fetch('GOODREADS_SECRET', nil) }
  config.filter_sensitive_data('<OVERDRIVE_KEY>') { ENV.fetch('OVERDRIVE_KEY', nil) }
  config.filter_sensitive_data('<OVERDRIVE_SECRET>') { ENV.fetch('OVERDRIVE_SECRET', nil) }
  config.filter_sensitive_data('<BOOKMOOCH_USERNAME>') { ENV.fetch('BOOKMOOCH_USERNAME', nil) }
  config.filter_sensitive_data('<BOOKMOOCH_PASSWORD>') { ENV.fetch('BOOKMOOCH_PASSWORD', nil) }
  config.filter_sensitive_data('<AUTHORIZATION>') { |i| i.request.headers['Authorization']&.first }
end

# VCR is off unless a spec asks for a cassette.
#
# Configuring VCR installs a global WebMock stub, and while an explicit
# stub_request still takes precedence, anything unstubbed then fails with
# VCR::Errors::UnhandledHTTPRequestError instead of WebMock's
# NetConnectNotAllowedError. WebMock's is the better error -- it names the
# request and prints a paste-ready stub_request snippet -- and it is the one
# most specs here want, since most of them stub rather than replay.
#
# Worth knowing: NetConnectNotAllowedError descends from Exception, not
# StandardError, so the `rescue StandardError` blocks throughout lib/ cannot
# swallow it. An unstubbed call fails the spec instead of being reported as an
# application-level error.
VCR.turn_off!

# One call, here rather than in each spec helper. `rake test` loads every spec
# file into one process, so two helpers calling disable_net_connect! with
# different options means the last one loaded wins -- which blocked Capybara's
# own http://127.0.0.1:9292/__identify__ handshake and failed every browser
# spec, but only under rake.
#
# allow_localhost covers Capybara's Falcon server and Selenium's driver
# connection. Nothing the app reaches for is on localhost, so this still fails
# a spec that forgets to stub Goodreads, OverDrive, BookMooch or OpenLibrary.
WebMock.disable_net_connect! allow_localhost: true

module CassetteHelpers
  # Replays a recorded interaction. Use for payloads too large to hand-build --
  # a paginated Goodreads shelf, an OverDrive availability batch. For anything
  # smaller, and for every error path, a stub_request states the case better.
  def with_cassette(name, **, &)
    # Clear registered stubs first: an explicit stub_request takes precedence
    # over VCR's global hook, so the spec/web defaults -- prepended onto every
    # Minitest::Test, and loaded whenever `rake test` pulls both spec trees
    # into one process -- would otherwise shadow the recording. Inside a
    # cassette block the recording is the source of truth.
    #
    # This also clears the request history, so assert_requested for calls made
    # before the block will not see them.
    WebMock.reset!
    VCR.turned_on { VCR.use_cassette(name, **, &) }
  end
end

Minitest::Test.include CassetteHelpers

# Builders for the response shapes the parsers expect.
#
# These are deliberately schema-complete rather than minimal. Goodreads.
# extract_books_from_body maps seven xpaths and transposes them, so a fixture
# missing one field produces ragged arrays and an IndexError from inside
# Array#transpose rather than a readable failure. Build payloads through these
# helpers instead of inline strings.
module HttpFixtures
  GOODREADS_HOST = 'https://www.goodreads.com'
  OVERDRIVE_LIBRARY_SEARCH = 'https://www.overdrive.com/mapbox/find-libraries-by-query'

  module_function

  # One <review> element, with every field BOOK_DETAILS looks for.
  def goodreads_review isbn: '9780062316097', title: 'Sapiens', author: 'Yuval Noah Harari', published: '2015', rating: '4'
    <<~XML
      <review>
        <book>
          <isbn13>#{isbn}</isbn13>
          <image_url>https://images.gr-assets.com/books/#{isbn}.jpg</image_url>
          <title>#{title}</title>
          <authors><author><name>#{author}</name></author></authors>
          <published>#{published}</published>
        </book>
        <rating>#{rating}</rating>
        <date_added>Mon Jan 01 00:00:00 -0800 2024</date_added>
      </review>
    XML
  end

  # A /review/list page. `total` drives the pagination arithmetic in
  # Goodreads.fetch_all_pages, so it must reflect the whole shelf, not the page.
  def goodreads_review_page reviews, page: 1, per_page: 100, total: nil
    start = ((page - 1) * per_page) + 1
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <GoodreadsResponse>
        <reviews start="#{start}" end="#{start + reviews.size - 1}" total="#{total || reviews.size}">
          #{reviews.join}
        </reviews>
      </GoodreadsResponse>
    XML
  end

  def goodreads_shelf_list shelves
    entries = shelves.map { |name, count| "<user_shelf><name>#{name}</name><book_count>#{count}</book_count></user_shelf>" }
    %(<?xml version="1.0" encoding="UTF-8"?><GoodreadsResponse><shelves>#{entries.join}</shelves></GoodreadsResponse>)
  end

  # What Akamai returns when a request arrives without a User-Agent. Goodreads
  # sits behind it, which is why DEFAULT_HEADERS exists in lib/goodreads.rb.
  def akamai_403_page
    <<~HTML
      <HTML><HEAD><TITLE>Access Denied</TITLE></HEAD>
      <BODY>You don't have permission to access "http://www.goodreads.com/review/list" on this server.
      Reference #18.a1b2c3d4.1726574400.5f6a7b8</BODY></HTML>
    HTML
  end

  def overdrive_library consortium_id: '1135', name: 'Seattle Public Library'
    {'consortiumId' => consortium_id, 'consortiumName' => name, 'consortiumLogo' => 'https://img.overdrive.com/logo.png'}
  end
end
