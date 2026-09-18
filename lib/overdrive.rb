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
require_relative 'overdrive/across_libraries'
require_relative 'overdrive/library_search'
require_relative 'title_normalizer'

class Overdrive
  BASE_URL     = 'https://api.overdrive.com'
  API_URI      = "#{BASE_URL}/v1".freeze
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

  # One copy of a book: a single format, at a single library.
  #
  # `format` is the product's OverDrive mediaType -- "ebook", "audiobook",
  # "video". It was read nowhere before, so every result was presented as an
  # ebook regardless of what the library actually holds.
  #
  # `library` is the consortium's display name, so the results page can say
  # where a copy is rather than only that one exists.
  #
  # `availability_url` used to sit here: declared, set to nil at both
  # construction sites, and read by nothing. It is gone.
  Title = Data.define(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)

  # What OverDrive calls a format, and what a person calls it.
  FORMAT_LABELS = {'ebook' => 'ebook', 'audiobook' => 'audiobook', 'video' => 'video'}.freeze
  DEFAULT_FORMAT = 'ebook'

  def self.format_label(format) = FORMAT_LABELS.fetch(format.to_s, DEFAULT_FORMAT)

  # How one book is identified across formats and libraries. The ISBN comes
  # from Goodreads, so it is the same for every OverDrive product matched to
  # it; a book without one falls back to its normalised title.
  def self.book_key isbn, title
    isbn.to_s.empty? ? TitleNormalizer.normalize(title) : isbn
  end

  def self.local_libraries zip_code
    LibrarySearch.near zip_code
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

    # Ruby hash patterns only accept symbol keys, so the `in links: {...}` this
    # replaces never matched a JSON.parse result and @website_id was always
    # nil. views/availability.erb interpolates it straight into a borrow link,
    # so every availability result carried a "?websiteID=" pointing nowhere.
    if (homepage = body.dig('links', 'dlrHomepage', 'href')) && (match = homepage.match(/websiteID=(\d+)/))
      @website_id = match[1]
      @library_url = "https://link.overdrive.com/?websiteID=#{@website_id}"
    end

    body['collectionToken']
  end

  # The optional block is called after each chunk lands, so a caller streaming
  # to a browser has something to show. Chunks are the only honest unit of
  # progress here: within one, the OverDrive search, edition expansion and
  # availability lookup all run concurrently and finish out of order.
  def fetch_titles_availability &progress_callback
    total_start = monotonic_now
    rss_before = self.class.rss_mb
    chunks = @book_info.each_slice(CHUNK_SIZE).to_a
    warn "[overdrive] Starting: #{@book_info.size} books in #{chunks.size} chunks, RSS=#{rss_before.round(1)}MB"

    results = Array.new(chunks.size)
    completed = 0
    task = Async do
      barrier = Async::Barrier.new
      chunks.each_with_index do |chunk, i|
        barrier.async do
          results[i] = process_chunk(chunk, i + 1, chunks.size)
          # Fibers on one thread, so this increment needs no lock.
          completed += 1
          report_chunk_progress(progress_callback, completed, chunks.size)
        end
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

  # A failure to report progress must never lose the availability results the
  # chunk just produced -- the socket may have closed while this ran.
  def report_chunk_progress callback, completed, total
    callback&.call(type: 'progress', message: "Checking availability — #{completed} of #{total} batches complete...", current: completed, total: total)
  rescue StandardError
    nil
  end

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
      format: DEFAULT_FORMAT,
      library: nil,
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
          format: edition['mediaType'].to_s.downcase.then { |media| media.empty? ? DEFAULT_FORMAT : media },
          library: book.library,
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

  # Consolidate duplicate editions across all titles.
  #
  # Keyed on format as well as identifier. Keying on identifier alone collapsed
  # every format of a title into one row and kept whichever had the most copies
  # -- so a library with the audiobook but not the ebook showed the audiobook
  # labelled "Read". The ISBN carried here is the Goodreads one, which is the
  # same for every format OverDrive returned, so it cannot separate them.
  def consolidate_duplicate_titles titles
    books_by_key = {}
    titles.each do |book|
      key = [self.class.book_key(book.isbn, book.title), book.format]
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

  # The path for a book Goodreads has no ISBN for. Same widening as the ISBN
  # path: a book held as both an ebook and an audiobook should show both,
  # rather than whichever OverDrive listed first.
  def validate_title_search_results client, search_body, target_author, target_title
    return {'products' => []}.to_json if no_products?(search_body)

    matched = find_matching_products_via_metadata(client, search_body, nil, target_author, target_title)
    return {'products' => matched}.to_json unless matched.empty?

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
    matched = find_matching_products_via_metadata(client, title_body, book[:isbn], book[:author], book[:title])
    return {'products' => matched}.to_json unless matched.empty?

    isbn_search_body
  rescue StandardError
    isbn_search_body
  ensure
    response&.close
  end

  # Every format that matches, rather than whichever OverDrive returned first.
  #
  # This used to stop at the first author-and-title match. The title search
  # comes back with both formats mixed -- measured at four audiobooks and six
  # ebooks in a ten-result page -- and OverDrive returns audiobooks first, so
  # five of five books tested resolved to the audiobook. A reader looking at
  # their want-to-read shelf was shown the audiobook of everything and the
  # ebook of nothing (#1395).
  #
  # One product per format, not every match: the search returns several
  # editions of each -- different narrators, different publishers -- and
  # consolidate_duplicate_titles would collapse them to one row per format
  # anyway. Keeping them all would multiply the availability lookups that
  # follow for results nobody sees.
  def find_matching_products_via_metadata client, search_body, target_isbn, target_author, target_title
    parsed = JSON.parse(search_body)
    overdrive_results = parsed['products']
    return [] unless overdrive_results && !overdrive_results.empty?

    matches = overdrive_results.select do |product|
      next false unless Matching.author_matches?(product, target_author)
      # Title first: it is free, and it is what almost always decides. The
      # ISBN check reaches OpenLibrary, and this now runs per product rather
      # than stopping at the first.
      next true if Matching.title_matches_exactly?(product, target_title)

      target_isbn && !target_isbn.empty? && isbn_matches_in_metadata?(client, product, target_isbn)
    end

    matches.uniq { |product| product['mediaType'].to_s.downcase }
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
