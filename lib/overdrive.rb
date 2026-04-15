# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'async/http/internet'
require 'async/semaphore'
require 'oauth2'
require 'uri'
require_relative 'alternate_isbns'
require_relative 'title_normalizer'

class Overdrive
  BASE_URL     = 'https://api.overdrive.com'
  API_URI      = "#{BASE_URL}/v1".freeze
  MAPBOX_URI   = 'https://www.overdrive.com/mapbox/find-libraries-by-query'
  OAUTH_URI    = 'https://oauth.overdrive.com'
  KEY          = ENV.fetch('OVERDRIVE_KEY')
  SECRET       = ENV.fetch('OVERDRIVE_SECRET')
  CHUNK_SIZE   = 100

  module Matching
    module_function

    def title_matches_exactly? product, target_title
      product_title = product['title']
      return false unless product_title

      normalized_overdrive = TitleNormalizer.normalize(product_title)
      normalized_goodreads = TitleNormalizer.normalize(target_title)
      return true if normalized_overdrive == normalized_goodreads
      return true if normalized_goodreads.start_with?(normalized_overdrive)
      return true if normalized_overdrive.start_with?(normalized_goodreads)

      false
    end

    def author_matches? product, target_author
      product_author = product.dig('primaryCreator', 'name')
      return false unless product_author
      return false if target_author.nil? || target_author.empty?

      author_last_name = target_author.split.last.downcase
      product_author.downcase.include?(author_last_name)
    end
  end

  Title = Data.define(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :availability_url, :no_isbn, :date_added)

  def self.local_libraries zip_code
    task = Async do
      internet = Async::HTTP::Internet.new
      params = URI.encode_www_form query: zip_code, includePublicLibraries: true, includeSchoolLibraries: false
      headers = [
        ['user-agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'],
        ['referer', 'https://www.overdrive.com/libraries']
      ]
      response = internet.get "#{MAPBOX_URI}?#{params}", headers
      response.read
    ensure
      internet&.close
    end
    libraries = JSON.parse task.wait
    libraries.first(10).map { |l| [l['consortiumId'], l['consortiumName'], l['consortiumLogo']] }
  end

  def self.rss_mb
    status_path = "/proc/#{Process.pid}/status"
    kb = File.exist?(status_path) ? File.read(status_path)[/VmRSS:\s+(\d+)/, 1].to_i : `ps -o rss= -p #{Process.pid}`.to_i
    kb / 1024.0
  rescue StandardError
    0.0
  end

  def initialize book_info, consortium_id
    @book_info = book_info
    @token = token
    @consortium_id = consortium_id
    @collection_token = fetch_collection_token consortium_id, @token
    @timings = {}
  end

  attr_reader :collection_token, :website_id, :library_url, :timings

  def token
    client = OAuth2::Client.new KEY, SECRET, token_url: '/token', site: OAUTH_URI
    client.client_credentials.get_token.token
  end

  def fetch_collection_token consortium_id, token
    library_uri = "#{API_URI}/libraries/#{consortium_id}"

    task = Async do
      internet = Async::HTTP::Internet.new
      response = internet.get(library_uri, {'Authorization' => "Bearer #{token}"})
      response.read
    ensure
      internet&.close
    end

    body = JSON.parse task.wait
    case body
    in links: {dlrHomepage: {href: String => url}} if url =~ /websiteID=(\d+)/
      @website_id = ::Regexp.last_match(1)
      @library_url = "https://link.overdrive.com/?websiteID=#{@website_id}"
    else
      nil
    end

    body['collectionToken']
  end

  def fetch_titles_availability
    total_start = monotonic_now
    rss_before = self.class.rss_mb
    chunks = @book_info.each_slice(CHUNK_SIZE).to_a
    warn "[overdrive] Starting: #{@book_info.size} books in #{chunks.size} chunks, RSS=#{rss_before.round(1)}MB"

    results = Array.new(chunks.size)
    task = Async do
      barrier = Async::Barrier.new
      chunks.each_with_index do |chunk, i|
        barrier.async { results[i] = process_chunk(chunk, i + 1, chunks.size) }
      end
      barrier.wait
    ensure
      barrier&.stop
    end
    task.wait
    all_titles = results.flatten
    consolidated = consolidate_duplicate_titles(all_titles)
    record_timings(rss_before, total_start, chunks.size, consolidated.size)
    consolidated.sort_by { |t| [t.copies_available, t.copies_owned] }.reverse
  end

  private

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def process_chunk chunk, chunk_num, chunk_count
    start = monotonic_now
    result = fetch_availability(expand_editions(search_chunk(chunk)))
    elapsed = (monotonic_now - start).round(2)
    warn "[overdrive] Chunk #{chunk_num}/#{chunk_count}: #{chunk.size} books, #{elapsed}s, RSS=#{self.class.rss_mb.round(1)}MB"
    result
  end

  def record_timings rss_before, total_start, chunk_count, titles_count
    elapsed = (monotonic_now - total_start).round(2)
    rss_after = self.class.rss_mb.round(1)
    delta = (rss_after - rss_before).round(1)
    @timings = {
      total_books: @book_info.size,
      chunk_count:,
      total_elapsed: elapsed,
      rss_before: rss_before.round(1),
      rss_after:,
      rss_delta: delta,
      titles_returned: titles_count
    }
    warn "[overdrive] Done: #{elapsed}s, #{titles_count} titles, RSS #{rss_before.round(1)}->#{rss_after}MB (delta #{delta}MB)"
  end

  def should_replace? candidate, current
    candidate.copies_available.to_i > current.copies_available.to_i
  end

  def title book, no_isbn: false
    Title.new(
      isbn: book[:isbn],
      image: book[:image_url],
      title: book[:title],
      author: book[:author],
      copies_available: 0,
      copies_owned: 0,
      url: nil,
      id: nil,
      availability_url: nil,
      no_isbn: no_isbn,
      date_added: book[:date_added]
    )
  end

  def availability_path book
    isbn = book[:isbn]
    query = isbn && !isbn.empty? ? isbn : "\"#{TitleNormalizer.clean_for_search(book[:title])}\""
    "/v1/collections/#{@collection_token}/products?#{URI.encode_www_form(minimum: false, limit: 5, q: query)}"
  end

  # Search Overdrive catalog for a chunk of books. Returns [[Title, body_string], ...]
  def search_chunk chunk
    async_result = Async do |_task|
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(16, parent: barrier)
      books = []
      chunk.each do |book|
        semaphore.async { books << fetch_book_data(client, book) }
      end
      begin
        barrier.wait
      ensure
        barrier&.stop
      end
      books
    ensure
      client&.close
    end
    async_result.wait
  end

  # Parse raw bodies into expanded Title objects, discarding raw JSON strings
  def expand_editions books_with_bodies
    expanded = []
    books_with_bodies.each do |book, body|
      unless body
        expanded << book
        next
      end

      overdrive_editions = JSON.parse(body)['products']
      unless overdrive_editions && !overdrive_editions.empty?
        expanded << book
        next
      end
      overdrive_editions.each do |edition|
        expanded << Title.new(
          title: book.title,
          author: book.author,
          image: edition.dig('images', 'cover300Wide', 'href') || book.image,
          copies_available: 0,
          copies_owned: 0,
          isbn: book.isbn,
          url: edition.dig('contentDetails', 0, 'href'),
          id: edition['id'],
          availability_url: nil,
          no_isbn: book.no_isbn,
          date_added: book.date_added
        )
      end
    end
    expanded
  end

  # Fetch availability for a list of Title objects, returns updated Title array
  def fetch_availability titles
    titles_with_ids = titles.select(&:id)
    return titles if titles_with_ids.empty?

    id_batches = titles_with_ids.map(&:id).each_slice(25)
    responses = async_availability_responses(id_batches).wait

    # Build a lookup from reserveId -> availability data
    availability_map = {}
    responses.each do |raw_body, status|
      next if status >= 400

      body = JSON.parse raw_body
      body['availability']&.each do |result|
        reserve_id = result['reserveId']&.downcase
        availability_map[reserve_id] = result if reserve_id
      end
    end

    titles.map do |t|
      if t.id && (avail = availability_map[t.id.downcase])
        t.with(copies_available: avail['copiesAvailable'], copies_owned: avail['copiesOwned'])
      else
        t
      end
    end
  end

  # Consolidate duplicate editions across all titles
  def consolidate_duplicate_titles titles
    books_by_key = {}
    titles.each do |book|
      key = book.isbn&.then { |isbn| isbn.empty? ? nil : isbn } || TitleNormalizer.normalize(book.title)
      if books_by_key[key]
        books_by_key[key] = book if should_replace?(book, books_by_key[key])
      else
        books_by_key[key] = book
      end
    end
    books_by_key.values
  end

  def fetch_book_data client, book
    response = client.get(availability_path(book), {'Authorization' => "Bearer #{@token}"})
    body = response.read
    response.close
    no_isbn = missing_isbn?(book)
    body = if no_isbn
      validate_title_search_results(client, body, book[:author], book[:title])
    else
      try_title_search_with_metadata(client, book, body)
    end
    [title(book, no_isbn: no_isbn), body]
  rescue StandardError
    [title(book, no_isbn: missing_isbn?(book)), nil]
  ensure
    response&.close
  end

  def missing_isbn?(book) = book[:isbn].nil? || book[:isbn].empty?

  def no_products?(body) = JSON.parse(body)['products']&.empty? != false

  def validate_title_search_results client, search_body, target_author, target_title
    return {'products' => []}.to_json if no_products?(search_body)

    matched_product = find_matching_product_via_metadata(client, search_body, nil, target_author, target_title)
    return {'products' => [matched_product]}.to_json if matched_product

    {'products' => []}.to_json
  rescue StandardError
    {'products' => []}.to_json
  end

  def try_title_search_with_metadata client, book, isbn_search_body
    return isbn_search_body unless no_products?(isbn_search_body)

    clean_title = TitleNormalizer.clean_for_search(book[:title])
    params = URI.encode_www_form minimum: false, limit: 10, q: "\"#{clean_title}\""
    path = "/v1/collections/#{@collection_token}/products?#{params}"
    response = client.get(path, {'Authorization' => "Bearer #{@token}"})
    title_body = response.read
    response.close
    matched_product = find_matching_product_via_metadata(client, title_body, book[:isbn], book[:author], book[:title])
    return {'products' => [matched_product]}.to_json if matched_product

    isbn_search_body
  rescue StandardError
    isbn_search_body
  ensure
    response&.close
  end

  def find_matching_product_via_metadata client, search_body, target_isbn, target_author, target_title
    parsed = JSON.parse(search_body)
    overdrive_results = parsed['products']
    return unless overdrive_results && !overdrive_results.empty?

    overdrive_results.each do |overdrive_book|
      next unless Matching.author_matches?(overdrive_book, target_author)
      return overdrive_book if target_isbn && !target_isbn.empty? && isbn_matches_in_metadata?(client, overdrive_book, target_isbn)
      return overdrive_book if Matching.title_matches_exactly?(overdrive_book, target_title)
    end
    nil
  end

  def isbn_matches_in_metadata? _client, _product, target_isbn
    (AlternateIsbns.fetch_alternate_isbns([target_isbn])[target_isbn] || []).include?(target_isbn)
  end

  def async_availability_responses batches
    Async do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(16, parent: barrier)
      responses = []
      batches.each.with_index 1 do |batch, _batch_number|
        params = URI.encode_www_form products: batch.join(',')
        path = "/v2/collections/#{@collection_token}/availability?#{params}"
        semaphore.async do
          response = client.get path, {'Authorization' => "Bearer #{@token}"}
          responses << [response.read, response.status]
        ensure
          response&.close
        end
      end
      begin
        barrier.wait
      ensure
        barrier&.stop
      end
      responses
    ensure
      client&.close
    end
  end
end
