# frozen_string_literal: true

require_relative 'spec_helper'
require 'overdrive'

# Checking several libraries for one shelf. Split from
# overdrive_availability_http_spec.rb, which covers a single library end to end.
describe 'Overdrive.fetch_across_libraries' do
  COLLECTION_TOKEN = 'v1L3JhbXA'

  def stub_token
    stub_request(:post, 'https://oauth.overdrive.com/token')
      .to_return(status: 200,
                 headers: {'Content-Type' => 'application/json'},
                 body: JSON.dump({'access_token' => 'od-token', 'token_type' => 'bearer', 'expires_in' => 3600}))
  end

  let(:book) { {isbn: '9780062316097', title: 'Sapiens', author: 'Yuval Noah Harari', image_url: 'gr.jpg', date_added: '2024-01-01'} }

  # #1390. Every library is a full extra pass over the shelf -- the search is
  # scoped to a collection token, so each book is searched again per consortium
  # -- and that search is already the slowest thing the app does.
  describe '.fetch_across_libraries' do
    BROOKLYN = '1135'
    NYPL = '4242'

    def stub_consortium id, collection:
      stub_request(:get, "https://api.overdrive.com/v1/libraries/#{id}").to_return(
        status: 200,
        body: JSON.dump({'collectionToken' => collection, 'links' => {'dlrHomepage' => {'href' => "https://x.overdrive.com/?websiteID=#{id}"}}})
      )
    end

    def stub_collection collection, available:
      stub_request(:get, %r{/v1/collections/#{collection}/products}).to_return(
        status: 200,
        # Title and author are what the matcher narrows on, now that every
        # lookup goes by title (#1394).
        body: JSON.dump(
          {
            'products' => [
              {
                'id' => "#{collection}-1",
                'mediaType' => 'ebook',
                'title' => 'Sapiens',
                'primaryCreator' => {'name' => 'Yuval Noah Harari'},
                'images' => {},
                'contentDetails' => []
              }
            ]
          }
        )
      )
      stub_request(:get, %r{/v2/collections/#{collection}/availability}).to_return(
        status: 200,
        body: JSON.dump({'availability' => [{'reserveId' => "#{collection}-1", 'copiesAvailable' => available, 'copiesOwned' => 5}]})
      )
    end

    def libraries = [[BROOKLYN, 'Brooklyn'], [NYPL, 'NYPL']]

    before do
      stub_token
      stub_consortium BROOKLYN, collection: 'brooklyn'
      stub_consortium NYPL, collection: 'nypl'
    end

    it 'names the library each copy came from' do
      stub_collection 'brooklyn', available: 0
      stub_collection 'nypl', available: 2

      result = Overdrive.fetch_across_libraries([book], libraries)

      assert_equal %w[Brooklyn NYPL], result.copies.map(&:library).sort
    end

    # The whole point: an available copy ends the reader's question, so the
    # second library is never asked about that book.
    it 'stops searching a book once it is available somewhere' do
      stub_collection 'brooklyn', available: 3
      stub_collection 'nypl', available: 1

      result = Overdrive.fetch_across_libraries([book], libraries)

      assert_equal %w[Brooklyn], result.copies.map(&:library)
      assert_not_requested :get, %r{/v1/collections/nypl/products}
    end

    # Waitlisted and not-owned books are the ones where another library changes
    # the answer, so those do go on to the next.
    it 'keeps searching a book that is only waitlisted' do
      stub_collection 'brooklyn', available: 0
      stub_collection 'nypl', available: 4

      result = Overdrive.fetch_across_libraries([book], libraries)

      assert_requested :get, %r{/v1/collections/nypl/products}, times: 1
      assert_equal [0, 4], result.copies.map(&:copies_available).sort
    end

    it 'stops early when nothing is left to look for' do
      stub_collection 'brooklyn', available: 1

      Overdrive.fetch_across_libraries([book], libraries)

      # Not even the library lookup for the second consortium.
      assert_not_requested :get, "https://api.overdrive.com/v1/libraries/#{NYPL}"
    end

    it 'collects a deep link per library' do
      stub_collection 'brooklyn', available: 0
      stub_collection 'nypl', available: 0

      urls = Overdrive.fetch_across_libraries([book], libraries).library_urls

      assert_equal %w[Brooklyn NYPL], urls.keys.sort
      assert_equal "https://link.overdrive.com/?websiteID=#{BROOKLYN}", urls['Brooklyn']
    end

    it 'does nothing when no library was chosen' do
      result = Overdrive.fetch_across_libraries([book], [])

      assert_empty result.copies
      assert_empty result.library_urls
    end
  end
end
