# frozen_string_literal: true

require_relative 'spec_helper'
require 'overdrive'

# The OverDrive pipeline end to end at the HTTP layer: OAuth2 token, collection
# token, per-book product search, then batched availability. Every step here is
# a network call the suite previously went around, and the availability merge
# in particular is the number the whole feature exists to show.
describe 'Overdrive availability over HTTP' do
  COLLECTION = 'v1L3JhbXA'
  RESERVE_ID = 'A1B2C3D4-0000-1111-2222-333344445555'

  def stub_token
    stub_request(:post, 'https://oauth.overdrive.com/token')
      .to_return(status: 200,
                 headers: {'Content-Type' => 'application/json'},
                 body: JSON.dump({'access_token' => 'od-token', 'token_type' => 'bearer', 'expires_in' => 3600}))
  end

  def stub_library
    stub_request(:get, 'https://api.overdrive.com/v1/libraries/1135').to_return(
      status: 200,
      body: JSON.dump({'collectionToken' => COLLECTION, 'links' => {'dlrHomepage' => {'href' => 'https://seattle.overdrive.com/?websiteID=87'}}})
    )
  end

  def stub_product_search id: RESERVE_ID
    stub_request(:get, %r{/v1/collections/#{COLLECTION}/products}o).to_return(
      status: 200,
      body: JSON.dump(
        {
          'products' => [
            {
              'id' => id,
              'images' => {'cover300Wide' => {'href' => 'https://img.overdrive.com/cover.jpg'}},
              'contentDetails' => [{'href' => 'https://link.overdrive.com/?content=1'}],
              'primaryCreator' => {'name' => 'Yuval Noah Harari'}
            }
          ]
        }
      )
    )
  end

  def stub_availability copies_available: 3, copies_owned: 5, id: RESERVE_ID, status: 200
    stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(
      status: status,
      body: JSON.dump({'availability' => [{'reserveId' => id, 'copiesAvailable' => copies_available, 'copiesOwned' => copies_owned}]})
    )
  end

  let(:book) { {isbn: '9780062316097', title: 'Sapiens', author: 'Yuval Noah Harari', image_url: 'gr.jpg', date_added: '2024-01-01'} }

  before do
    stub_token
    stub_library
  end

  it 'reads the collection token and website id out of the library response' do
    overdrive = Overdrive.new([book], '1135')

    assert_equal COLLECTION, overdrive.collection_token
    assert_equal 'https://link.overdrive.com/?websiteID=87', overdrive.library_url
  end

  it 'sends the bearer token it got from the OAuth2 exchange' do
    stub_product_search
    stub_availability

    Overdrive.new([book], '1135').fetch_titles_availability

    assert_requested(:get, 'https://api.overdrive.com/v1/libraries/1135', headers: {'Authorization' => 'Bearer od-token'})
  end

  it 'searches by ISBN when the book has one' do
    stub_product_search
    stub_availability

    Overdrive.new([book], '1135').fetch_titles_availability

    assert_requested(:get, /products.*q=9780062316097/, times: 1)
  end

  it 'merges copy counts onto the title' do
    stub_product_search
    stub_availability copies_available: 3, copies_owned: 5

    title = Overdrive.new([book], '1135').fetch_titles_availability.first

    assert_equal 'Sapiens', title.title
    assert_equal 3, title.copies_available
    assert_equal 5, title.copies_owned
  end

  it 'matches reserve ids case-insensitively' do
    # The search returns one casing and availability another; the code
    # downcases both sides, and nothing proved it.
    stub_product_search id: RESERVE_ID.upcase
    stub_availability id: RESERVE_ID.downcase

    assert_equal 3, Overdrive.new([book], '1135').fetch_titles_availability.first.copies_available
  end

  it 'leaves copy counts at zero when the availability call fails' do
    # A failed batch must not drop the book from the results -- the user still
    # sees it, listed as unavailable.
    stub_product_search
    stub_availability status: 503

    title = Overdrive.new([book], '1135').fetch_titles_availability.first

    assert_equal 'Sapiens', title.title
    assert_equal 0, title.copies_available
  end

  it 'keeps a book the catalog does not carry, with no copies' do
    stub_request(:get, %r{/v1/collections/#{COLLECTION}/products}o).to_return(status: 200, body: JSON.dump({'products' => []}))

    titles = Overdrive.new([book], '1135').fetch_titles_availability

    assert_equal %w[Sapiens], titles.map(&:title)
    assert_equal 0, titles.first.copies_available
  end

  it 'batches availability at 25 product ids per request' do
    books = Array.new(30) { |i| {isbn: "978006231609#{i}", title: "Book #{i}", author: 'A', image_url: 'i', date_added: '2024-01-01'} }
    stub_request(:get, %r{/v1/collections/#{COLLECTION}/products}o).to_return do |request|
      isbn = request.uri.query_values['q']
      {status: 200, body: JSON.dump({'products' => [{'id' => "id-#{isbn}", 'images' => {}, 'contentDetails' => []}]})}
    end
    stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(status: 200, body: JSON.dump({'availability' => []}))

    Overdrive.new(books, '1135').fetch_titles_availability

    # 30 ids over a batch size of 25 is two requests, not one and not thirty.
    assert_requested(:get, %r{/v2/collections/#{COLLECTION}/availability}o, times: 2)
  end

  # #542. The search sends no format filter, so a title the library holds as
  # both an ebook and an audiobook comes back as two products. Nothing read
  # mediaType, so they collapsed into one row labelled "Read".
  describe 'formats' do
    def stub_products *products
      stub_request(:get, %r{/v1/collections/#{COLLECTION}/products}o).to_return(status: 200, body: JSON.dump({'products' => products}))
    end

    def product id:, media_type:
      {'id' => id, 'mediaType' => media_type, 'images' => {}, 'contentDetails' => [{'href' => "https://link.overdrive.com/?#{id}"}]}
    end

    it 'carries the product mediaType onto the title' do
      stub_products product(id: 'a1', media_type: 'audiobook')
      stub_availability id: 'a1'

      assert_equal 'audiobook', Overdrive.new([book], '1135').fetch_titles_availability.first.format
    end

    it 'keeps each format as its own result' do
      # Keyed on identifier alone, these became one row -- and since
      # should_replace? keeps whichever has the most copies, the audiobook
      # could win and be presented as an ebook.
      stub_products product(id: 'ebook-1', media_type: 'eBook'), product(id: 'audio-1', media_type: 'audiobook')
      stub_request(:get, %r{/v2/collections/#{COLLECTION}/availability}o).to_return(
        status: 200,
        body: JSON.dump(
          {
            'availability' => [
              {'reserveId' => 'ebook-1', 'copiesAvailable' => 1, 'copiesOwned' => 2},
              {'reserveId' => 'audio-1', 'copiesAvailable' => 9, 'copiesOwned' => 9}
            ]
          }
        )
      )

      titles = Overdrive.new([book], '1135').fetch_titles_availability

      assert_equal %w[audiobook ebook], titles.map(&:format).sort
      assert_equal [1, 9], titles.map(&:copies_available).sort
    end

    it 'normalises the casing OverDrive uses' do
      stub_products product(id: 'a1', media_type: 'eBook')
      stub_availability id: 'a1'

      assert_equal 'ebook', Overdrive.new([book], '1135').fetch_titles_availability.first.format
    end

    it 'falls back to ebook when a product carries no mediaType' do
      stub_products({'id' => 'a1', 'images' => {}, 'contentDetails' => []})
      stub_availability id: 'a1'

      assert_equal 'ebook', Overdrive.new([book], '1135').fetch_titles_availability.first.format
    end

    it 'gives a book the catalog does not carry a format anyway' do
      # The view reads .format on every row, including the placeholder for a
      # book with no matched product.
      stub_products

      assert_equal 'ebook', Overdrive.new([book], '1135').fetch_titles_availability.first.format
    end

    it 'labels a format for a reader' do
      assert_equal 'audiobook', Overdrive.format_label('audiobook')
      assert_equal 'ebook', Overdrive.format_label(nil)
      assert_equal 'ebook', Overdrive.format_label('something-new')
    end
  end
end
