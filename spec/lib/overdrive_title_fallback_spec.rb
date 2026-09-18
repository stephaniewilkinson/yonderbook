# frozen_string_literal: true

require_relative 'spec_helper'
require 'overdrive'

# The title-search fallback, which in practice is the only search that ever
# matches: q=<isbn> returns nothing at OverDrive, so every book falls through
# to it (#1394).
describe 'Overdrive title-search fallback' do
  COLLECTION = 'v1L3JhbXA'

  def stub_token
    stub_request(:post, 'https://oauth.overdrive.com/token')
      .to_return(status: 200,
                 headers: {'Content-Type' => 'application/json'},
                 body: JSON.dump({'access_token' => 'od-token', 'token_type' => 'bearer', 'expires_in' => 3600}))
  end

  def stub_library
    stub_request(:get, 'https://api.overdrive.com/v1/libraries/1135').to_return(
      status: 200,
      body: JSON.dump({'collectionToken' => COLLECTION, 'links' => {'dlrHomepage' => {'href' => 'https://s.overdrive.com/?websiteID=83'}}})
    )
  end

  let(:book) { {isbn: '9780062316097', title: 'Sapiens', author: 'Yuval Noah Harari', image_url: 'gr.jpg', date_added: '2024-01-01'} }

  before do
    stub_token
    stub_library
  end

  # #1395. The ISBN search returns nothing at OverDrive -- q= does not index
  # ISBNs -- so every book falls through to a title search, which comes back
  # with both formats mixed. The matcher used to take the first, and OverDrive
  # lists audiobooks first, so readers were shown the audiobook of everything.
  describe 'the title-search fallback' do
    def product id:, media_type:, title: 'Sapiens', author: 'Yuval Noah Harari'
      {
        'id' => id,
        'mediaType' => media_type,
        'title' => title,
        'primaryCreator' => {'name' => author},
        'images' => {},
        'contentDetails' => []
      }
    end

    # An ISBN query that finds nothing, then a title query that finds both
    # formats -- which is what the live API actually does.
    def stub_title_search *title_products
      stub_request(:get, %r{/v1/collections/#{COLLECTION}/products\?.*q=9780062316097}o).to_return(status: 200, body: JSON.dump({'products' => []}))
      stub_request(:get, %r{/v1/collections/#{COLLECTION}/products\?.*q=%22}o).to_return(status: 200, body: JSON.dump({'products' => title_products}))
    end

    it 'keeps both formats rather than the first one listed' do
      # Audiobook first, exactly as OverDrive orders them.
      stub_title_search product(id: 'audio-1', media_type: 'Audiobook'), product(id: 'ebook-1', media_type: 'eBook')
      stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(
        status: 200,
        body: JSON.dump(
          {
            'availability' => [
              {'reserveId' => 'audio-1', 'copiesAvailable' => 1, 'copiesOwned' => 2},
              {'reserveId' => 'ebook-1', 'copiesAvailable' => 3, 'copiesOwned' => 4}
            ]
          }
        )
      )

      titles = Overdrive.new([book], '1135').fetch_titles_availability

      assert_equal %w[audiobook ebook], titles.map(&:format).sort
    end

    it 'no longer resolves a two-format book to the audiobook alone' do
      stub_title_search product(id: 'audio-1', media_type: 'Audiobook'), product(id: 'ebook-1', media_type: 'eBook')
      stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(status: 200, body: JSON.dump({'availability' => []}))

      formats = Overdrive.new([book], '1135').fetch_titles_availability.map(&:format)

      assert_includes formats, 'ebook', 'the ebook was dropped, which is the bug'
    end

    # The search returns several editions per format -- different narrators,
    # different publishers. Consolidation would collapse them anyway, and
    # keeping them all multiplies the availability lookups that follow.
    it 'keeps one product per format, not every edition' do
      stub_title_search product(id: 'audio-1', media_type: 'Audiobook'),
                        product(id: 'audio-2', media_type: 'Audiobook'),
                        product(id: 'ebook-1', media_type: 'eBook'),
                        product(id: 'ebook-2', media_type: 'eBook')
      stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(status: 200, body: JSON.dump({'availability' => []}))

      titles = Overdrive.new([book], '1135').fetch_titles_availability

      assert_equal 2, titles.size
      assert_equal %w[audiobook ebook], titles.map(&:format).sort
    end

    it 'ignores a product by another author' do
      stub_title_search product(id: 'other-1', media_type: 'eBook', author: 'Someone Else'), product(id: 'audio-1', media_type: 'Audiobook')
      stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(status: 200, body: JSON.dump({'availability' => []}))

      titles = Overdrive.new([book], '1135').fetch_titles_availability

      assert_equal %w[audiobook], titles.map(&:format)
    end

    it 'still returns the book with no copies when nothing matches' do
      stub_title_search product(id: 'other-1', media_type: 'eBook', title: 'Something Else', author: 'Someone Else')

      titles = Overdrive.new([book], '1135').fetch_titles_availability

      assert_equal %w[Sapiens], titles.map(&:title)
      assert_equal 0, titles.first.copies_available
    end
  end

  # #1394. A book with an ISBN used to cost two searches: `q=<isbn>`, which
  # never matched, and then the title search that actually works.
  describe 'searches per book' do
    def stub_title_hit
      stub_request(:get, %r{/v1/collections/#{COLLECTION}/products}o).to_return(
        status: 200,
        body: JSON.dump(
          {
            'products' => [
              {
                'id' => 'p-1',
                'mediaType' => 'eBook',
                'title' => 'Sapiens',
                'primaryCreator' => {'name' => 'Yuval Noah Harari'},
                'images' => {},
                'contentDetails' => []
              }
            ]
          }
        )
      )
      stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(status: 200, body: JSON.dump({'availability' => []}))
    end

    it 'searches once for a book with an ISBN' do
      stub_title_hit

      Overdrive.new([book], '1135').fetch_titles_availability

      assert_requested(:get, %r{/v1/collections/#{COLLECTION}/products}o, times: 1)
    end

    it 'searches once for a book without one' do
      stub_title_hit

      Overdrive.new([book.merge(isbn: nil)], '1135').fetch_titles_availability

      assert_requested(:get, %r{/v1/collections/#{COLLECTION}/products}o, times: 1)
    end

    it 'never queries an ISBN, because OverDrive does not index them' do
      stub_title_hit

      Overdrive.new([book], '1135').fetch_titles_availability

      assert_not_requested(:get, /q=9780062316097/)
    end

    # isbn_matches_in_metadata? reached OpenLibrary and then asked whether an
    # ISBN appeared in its own list of alternates, never looking at the product
    # it was meant to be matching. It is gone, and so is the round trip.
    it 'reaches OpenLibrary not at all' do
      stub_title_hit

      Overdrive.new([book], '1135').fetch_titles_availability

      assert_not_requested(:get, /openlibrary\.org/)
    end
  end
end
