# frozen_string_literal: true

require_relative 'spec_helper'
require 'overdrive/library_search'

# LibrarySearch talks to OverDrive's public website rather than the
# authenticated API, so it gets HTML back when it is blocked or throttled --
# which some networks and CI runners do routinely. That path is handled at
# lib/overdrive/library_search.rb:42-51 and caught at lib/route_helpers.rb:58-64,
# and nothing exercised either until now.
describe 'Overdrive::LibrarySearch over HTTP' do
  FIND_LIBRARIES = %r{\Ahttps://www\.overdrive\.com/mapbox/find-libraries-by-query}

  it 'returns id, name and logo for each nearby consortium' do
    body = JSON.dump(
      [
        HttpFixtures.overdrive_library(consortium_id: '1135', name: 'Seattle Public Library'),
        HttpFixtures.overdrive_library(consortium_id: '4242', name: 'King County Library System')
      ]
    )
    stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: body)

    libraries = Overdrive::LibrarySearch.near '98101'

    assert_equal([['1135', 'Seattle Public Library'], ['4242', 'King County Library System']], libraries.map { |id, name, _logo| [id, name] })
  end

  it 'sends the zip code as given, leaving normalization to the caller' do
    # RouteHelpers#fetch_local_libraries strips spaces before it gets here
    # (lib/route_helpers.rb:59), so near itself passes the value through.
    stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: '[]')

    Overdrive::LibrarySearch.near '98101'

    assert_requested(:get, /query=98101/, times: 1)
  end

  it 'caps the list at MAX_RESULTS' do
    body = JSON.dump(Array.new(25) { |i| HttpFixtures.overdrive_library(consortium_id: i.to_s, name: "Library #{i}") })
    stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: body)

    assert_equal Overdrive::LibrarySearch::MAX_RESULTS, Overdrive::LibrarySearch.near('98101').size
  end

  it 'sends browser-ish headers, without which OverDrive blocks the request' do
    stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: '[]')

    Overdrive::LibrarySearch.near '98101'

    assert_requested(:get, FIND_LIBRARIES, headers: {'Referer' => 'https://www.overdrive.com/libraries'}, times: 1)
  end

  describe 'when OverDrive does not answer with JSON' do
    it 'raises ApiError naming the status on a 403' do
      stub_request(:get, FIND_LIBRARIES).to_return(status: 403, body: '<html><body>Access Denied</body></html>')

      error = assert_raises(Overdrive::ApiError) { Overdrive::LibrarySearch.near('98101') }

      assert_includes error.message, 'HTTP 403'
      assert_includes error.message, '98101'
    end

    it 'raises ApiError rather than JSON::ParserError when a 200 carries HTML' do
      # A throttled request answers 200 with an interstitial. Without the
      # rescue this surfaced as a bare JSON::ParserError with no context.
      stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: '<!DOCTYPE html><html><head><title>Just a moment</title></head></html>')

      error = assert_raises(Overdrive::ApiError) { Overdrive::LibrarySearch.near('98101') }

      assert_includes error.message, 'non-JSON'
      assert_includes error.message, '98101'
    end

    it 'treats an empty list as a real answer, not an error' do
      # No libraries near a zip code is legitimate and must not raise.
      stub_request(:get, FIND_LIBRARIES).to_return(status: 200, body: '[]')

      assert_empty Overdrive::LibrarySearch.near('99999')
    end
  end
end
