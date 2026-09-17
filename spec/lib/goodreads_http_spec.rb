# frozen_string_literal: true

require_relative 'spec_helper'
require 'goodreads'

# The failure modes Goodreads actually produces, exercised through the HTTP
# layer rather than around it. Stubbing Goodreads.fetch_shelves would skip the
# request building, the response parsing and the error handling -- which is all
# of the code these cover.
describe 'Goodreads over HTTP' do
  SHELF_LIST = %r{\Ahttps://www\.goodreads\.com/shelf/list\.xml}
  REVIEW_LIST = %r{\Ahttps://www\.goodreads\.com/review/list/}

  describe '.fetch_shelves' do
    it 'returns shelf names paired with counts' do
      stub_request(:get, SHELF_LIST).to_return(status: 200, body: HttpFixtures.goodreads_shelf_list([['to-read', 12], ['read', 40]]))

      assert_equal([['to-read', 12], ['read', 40]], Goodreads.fetch_shelves('42').map { |name, count| [name.to_s, count] })
    end

    it 'sends the User-Agent Akamai requires' do
      # lib/goodreads.rb:24-28: without one, Goodreads answers 403 HTML rather
      # than ever reaching the API. Nothing else in the suite proves we send it.
      stub_request(:get, SHELF_LIST).to_return(status: 200, body: HttpFixtures.goodreads_shelf_list([['read', 1]]))

      Goodreads.fetch_shelves('42')

      assert_requested(:get, SHELF_LIST, headers: {'User-Agent' => 'Yonderbook (+https://yonderbook.com)'})
    end

    it 'raises ApiError naming the status when Akamai answers 403 with HTML' do
      stub_request(:get, SHELF_LIST).to_return(status: 403, body: HttpFixtures.akamai_403_page)

      error = assert_raises(GoodreadsResponse::ApiError) { Goodreads.fetch_shelves('42') }

      assert_includes error.message, 'HTTP 403'
      assert_includes error.message, 'Access Denied'
    end

    it 'raises ApiError when a 200 omits the element instead of degrading to an empty list' do
      # A revoked key and an expired token both do this. Without the check it
      # would read as "this account has no shelves".
      stub_request(:get, SHELF_LIST).to_return(status: 200, body: '<?xml version="1.0"?><GoodreadsResponse><error>Invalid API key</error></GoodreadsResponse>')

      error = assert_raises(GoodreadsResponse::ApiError) { Goodreads.fetch_shelves('42') }

      assert_includes error.message, 'no //shelves'
      assert_includes error.message, 'Invalid API key'
    end

    it 'surfaces a connection failure rather than hanging' do
      stub_request(:get, SHELF_LIST).to_timeout

      assert_raises(StandardError) { Goodreads.fetch_shelves('42') }
    end
  end

  describe '.get_books' do
    it 'follows pagination and returns every book' do
      # total=250 at 100 per page means three requests. fetch_all_pages issues
      # pages 2 and 3 concurrently through a Barrier and Semaphore.
      3.times do |i|
        page = i + 1
        reviews = [HttpFixtures.goodreads_review(isbn: "978000000000#{page}", title: "Book #{page}")]
        stub_request(:get, %r{review/list.*page=#{page}(&|\z)}).to_return(
          status: 200,
          body: HttpFixtures.goodreads_review_page(reviews, page: page, total: 250)
        )
      end

      books = Goodreads.get_books('to-read', '42')

      assert_equal ['Book 1', 'Book 2', 'Book 3'], books.map { |b| b[:title] }.sort
      3.times { |i| assert_requested(:get, %r{review/list.*page=#{i + 1}(&|\z)}, times: 1) }
    end

    it 'parses every field the view needs off one review' do
      reviews = [HttpFixtures.goodreads_review(isbn: '9780062316097', title: 'Sapiens', author: 'Yuval Noah Harari', published: '2015', rating: '5')]
      stub_request(:get, REVIEW_LIST).to_return(status: 200, body: HttpFixtures.goodreads_review_page(reviews))

      book = Goodreads.get_books('to-read', '42').first

      assert_equal '9780062316097', book[:isbn]
      assert_equal 'Sapiens', book[:title]
      assert_equal 'Yuval Noah Harari', book[:author]
    end

    it 'raises ApiError on a 403 rather than returning an empty shelf' do
      stub_request(:get, REVIEW_LIST).to_return(status: 403, body: HttpFixtures.akamai_403_page)

      assert_raises(GoodreadsResponse::ApiError) { Goodreads.get_books('to-read', '42') }
    end
  end

  describe '.fetch_book_data' do
    it 'returns [:ok, book] for a 200' do
      stub_request(:get, %r{/book/isbn/9780062316097}).to_return(
        status: 200,
        body: '<GoodreadsResponse><book><title>Sapiens</title><image_url>i.jpg</image_url></book></GoodreadsResponse>'
      )

      status, book = Goodreads.fetch_book_data('9780062316097')

      assert_equal :ok, status
      assert_equal 'Sapiens', book.title
    end

    it 'returns [:error, status] for a non-200, which is the branch the view checks' do
      stub_request(:get, %r{/book/isbn/9780062316097}).to_return(status: 404, body: '')

      assert_equal [:error, 404], Goodreads.fetch_book_data('9780062316097')
    end
  end
end
