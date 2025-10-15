# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'async/http/internet'
require 'async/semaphore'
require 'oauth2'
require 'uri'
require_relative 'title_normalizer'

class Overdrive
  BASE_URL     = 'https://api.overdrive.com'
  API_URI      = "#{BASE_URL}/v1".freeze
  MAPBOX_URI   = 'https://www.overdrive.com/mapbox/find-libraries-by-query'
  OAUTH_URI    = 'https://oauth.overdrive.com'
  KEY          = ENV.fetch 'OVERDRIVE_KEY'
  SECRET       = ENV.fetch 'OVERDRIVE_SECRET'

  Title = Struct.new :title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :availability_url, :no_isbn, keyword_init: true

  def self.local_libraries zip_code
    # here is the url that overdrive uses to search
    # https://www.overdrive.com/mapbox/find-libraries-by-query?query=91302&includePublicLibraries=true&includeSchoolLibraries=true&sort=distance

    task = Async do
      internet = Async::HTTP::Internet.new
      params = URI.encode_www_form query: zip_code, includePublicLibraries: true, includeSchoolLibraries: false
      response = internet.get "#{MAPBOX_URI}?#{params}"
      response.read
    ensure
      internet&.close
    end
    libraries = JSON.parse task.wait
    libraries.first(10).map do |l|
      consortium_id = l['consortiumId']
      consortium_name = l['consortiumName']

      [consortium_id, consortium_name]
    end
  end

  def initialize book_info, consortium_id
    @book_info = book_info
    @token = token
    @consortium_id = consortium_id

    @collection_token = fetch_collection_token consortium_id, @token
    @books = async_books_with_overdrive_info.wait
  end

  attr_reader :collection_token, :website_id, :library_url

  def token
    client = OAuth2::Client.new KEY, SECRET, token_url: '/token', site: OAUTH_URI
    client.client_credentials.get_token.token
  end

  # Four digit library id from user submitted form, fetching the library-specific endpoint
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

    # Extract library website ID for search links
    if body['links'] && body['links']['dlrHomepage'] && body['links']['dlrHomepage']['href']
      homepage_url = body['links']['dlrHomepage']['href']
      # Extract websiteID from URL like "https://link.overdrive.com?websiteID=115"
      if homepage_url =~ /websiteID=(\d+)/
        @website_id = ::Regexp.last_match(1)
        # Construct the library URL base that works with search parameters
        @library_url = "https://link.overdrive.com/?websiteID=#{@website_id}"
      end
    end

    body['collectionToken']
  end

  def fetch_titles_availability
    add_id_and_url_to_books
    add_library_availability_to_books
    consolidate_duplicate_editions

    @books.map(&:first).sort_by { |book| [book.copies_available, book.copies_owned] }.reverse
  end

  def add_id_and_url_to_books
    # For each book, create entries for all returned product editions/formats
    expanded_books = []

    @books.each do |book, body|
      # Keep books with no body - they're unavailable
      unless body
        expanded_books << [book, body]
        next
      end

      overdrive_editions = JSON.parse(body)['products']

      # Keep books with no editions - they're unavailable
      unless overdrive_editions && !overdrive_editions.empty?
        expanded_books << [book, body]
        next
      end

      # Trust all editions returned from ISBN search
      overdrive_editions.each do |edition|
        book_copy = Title.new(
          title: book.title,
          author: book.author,
          image: edition.dig('images', 'cover300Wide', 'href') || book.image,
          copies_available: 0,
          copies_owned: 0,
          isbn: book.isbn,
          url: edition.dig('contentDetails', 0, 'href'),
          id: edition['id']
        )
        expanded_books << [book_copy, body]
      end
    end

    @books = expanded_books
  end

  def add_library_availability_to_books
    # TODO: expand this section to include links and ids for other book formats
    books_with_ids = @books.map(&:first).select(&:id)
    batches = books_with_ids.map(&:id).each_slice(25)

    responses = async_responses(batches).wait
    responses.each.with_index 1 do |(raw_body, status), _batch_number|
      body = JSON.parse raw_body

      if status >= 400
        # {"errorCode"=>"InternalError", "message"=>"An unexpected error has occurred.", "token"=>"8b0c9f8c-2c5c-41f4-8b32-907f23baf111"}
        next
      end

      body['availability'].each do |result|
        book = @books.find { |title, _| title.id&.downcase == result['reserveId']&.downcase }&.first
        next unless book

        book.copies_available = result['copiesAvailable']
        book.copies_owned = result['copiesOwned']
      end
    end
  end

  def consolidate_duplicate_editions
    # Group books by ISBN or title (for books without ISBN)
    # Prioritize: 1) editions with ANY availability, 2) most copies available
    books_by_key = {}

    @books.each do |book, body|
      # Use ISBN as key if available, otherwise use normalized title
      key = book.isbn&.empty? == false ? book.isbn : TitleNormalizer.normalize(book.title)

      if books_by_key[key]
        books_by_key[key] = [book, body] if should_replace?(book, books_by_key[key].first)
      else
        books_by_key[key] = [book, body]
      end
    end

    @books = books_by_key.values
  end

  private

  def should_replace? candidate_edition, current_best_edition
    # Replace if candidate edition has ANY availability and current best doesn't
    candidate_has_availability = candidate_edition.copies_available.to_i.positive?
    current_has_availability = current_best_edition.copies_available.to_i.positive?

    return true if candidate_has_availability && !current_has_availability
    return false if !candidate_has_availability && current_has_availability

    # Both have availability or both don't - choose the one with more copies
    candidate_edition.copies_available.to_i > current_best_edition.copies_available.to_i
  end

  def title book, no_isbn: false
    Title.new(isbn: book[:isbn], image: book[:image_url], title: book[:title], author: book[:author], copies_available: 0, copies_owned: 0, no_isbn: no_isbn)
  end

  def availability_path book
    # Prefer ISBN search for accuracy, fallback to title if no ISBN
    if book[:isbn] && !book[:isbn].empty?
      params = URI.encode_www_form minimum: false, limit: 5, q: book[:isbn]
    else
      # Normalize title for better search results (remove series info, subtitles)
      clean_title = TitleNormalizer.clean_for_search(book[:title])
      title = "\"#{clean_title}\""
      params = URI.encode_www_form minimum: false, limit: 5, q: title
    end

    "/v1/collections/#{@collection_token}/products?#{params}"
  end

  def async_books_with_overdrive_info
    Async do |_task|
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new

      books = []

      @book_info.each.with_index 1 do |book, _book_number|
        barrier.async { books << fetch_book_data(client, book) }
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
  end

  def fetch_book_data client, book
    # Search by ISBN if available, otherwise by title
    response = client.get(availability_path(book), {'Authorization' => "Bearer #{@token}"})
    body = response.read
    response.close

    # For books WITH ISBN: try title search + metadata check to find different editions
    # For books WITHOUT ISBN: validate results with title/author matching
    if missing_isbn?(book)
      # No ISBN - validate search results by title and author matching
      body = validate_title_search_results(client, body, book[:author], book[:title])
      [title(book, no_isbn: true), body]
    else
      # Has ISBN - try fallback title search if ISBN search found nothing
      body = try_title_search_with_metadata(client, book, body)
      [title(book), body]
    end
  rescue StandardError
    if missing_isbn?(book)
      [title(book, no_isbn: true), nil]
    else
      [title(book), nil]
    end
  ensure
    response&.close
  end

  def missing_isbn? book
    return false if book[:isbn] && !book[:isbn].empty?

    true
  end

  def no_products? body
    parsed = JSON.parse(body)
    !parsed['products'] || parsed['products'].empty?
  end

  def validate_title_search_results client, search_body, target_author, target_title
    # For books without ISBN, validate the title search results
    return {'products' => []}.to_json if no_products?(search_body)

    matched_product = find_matching_product_via_metadata(client, search_body, nil, target_author, target_title)
    return {'products' => [matched_product]}.to_json if matched_product

    # No valid match found
    {'products' => []}.to_json
  rescue StandardError
    {'products' => []}.to_json
  end

  def try_title_search_with_metadata client, book, isbn_search_body
    # If ISBN search found products, they matched the ISBN directly - accept them!
    return isbn_search_body unless no_products?(isbn_search_body)

    # ISBN search found nothing, fall back to title search
    # Remove series info and subtitles from search query as they break OverDrive search
    # e.g., "(Earthseed, #1)" and ": Mass Incarceration in the Age of Colorblindness"
    clean_title = TitleNormalizer.clean_for_search(book[:title])
    title_query = "\"#{clean_title}\""
    params = URI.encode_www_form minimum: false, limit: 10, q: title_query
    path = "/v1/collections/#{@collection_token}/products?#{params}"
    response = client.get(path, {'Authorization' => "Bearer #{@token}"})
    title_body = response.read
    response.close

    # For title search, we validate via metadata since the title search is fuzzy
    # Check if any product has the target ISBN in its metadata (other editions)
    matched_product = find_matching_product_via_metadata(client, title_body, book[:isbn], book[:author], book[:title])
    return {'products' => [matched_product]}.to_json if matched_product

    # No match found
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

    # Try to find match using ISBN first (more reliable), then fall back to title matching
    overdrive_results.each do |overdrive_book|
      next unless author_matches?(overdrive_book, target_author)

      # First priority: ISBN match in metadata (if target_isbn provided)
      return overdrive_book if target_isbn && !target_isbn.empty? && isbn_matches_in_metadata?(client, overdrive_book, target_isbn)

      # Second priority: exact title match (checked if ISBN didn't match OR no ISBN provided)
      return overdrive_book if title_matches_exactly?(overdrive_book, target_title)
    end

    nil
  end

  def title_matches_exactly? product, target_title
    product_title = product['title']
    return false unless product_title

    normalized_overdrive = TitleNormalizer.normalize(product_title)
    normalized_goodreads = TitleNormalizer.normalize(target_title)

    # Check for exact match
    return true if normalized_overdrive == normalized_goodreads

    # Check if OverDrive title matches the beginning of Goodreads title (handles subtitles)
    # e.g., "caps for sale" matches "caps for sale a tale of a peddler..."
    return true if normalized_goodreads.start_with?(normalized_overdrive)

    # Check if Goodreads title matches the beginning of OverDrive title
    # e.g., "caps for sale" matches "caps for sale a tale of a peddler..."
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

  def isbn_matches_in_metadata? client, product, target_isbn
    product_id = product['id']
    metadata = fetch_product_metadata(client, product_id)
    all_isbns = extract_all_isbns(metadata)

    all_isbns.include?(target_isbn)
  end

  def fetch_product_metadata client, product_id
    metadata_path = "/v1/collections/#{@collection_token}/products/#{product_id}/metadata"
    response = client.get(metadata_path, {'Authorization' => "Bearer #{@token}"})
    metadata_body = response.read
    response.close
    JSON.parse(metadata_body)
  rescue StandardError
    {} # Return empty hash on error
  ensure
    response&.close
  end

  def extract_all_isbns metadata
    isbns = []

    # Check formats array for ISBNs
    metadata['formats']&.each do |format|
      next unless format['identifiers']

      format['identifiers'].each do |identifier|
        isbns << identifier['value'] if identifier['type'] == 'ISBN'
      end
    end

    # Check otherFormatIdentifiers
    metadata['otherFormatIdentifiers']&.each do |identifier|
      isbns << identifier['value'] if identifier['type'] == 'ISBN'
    end

    isbns
  end

  def async_responses batches
    Async do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new

      responses = []

      batches.each.with_index 1 do |batch, batch_number|
        params = URI.encode_www_form products: batch.join(',')
        path = "/v2/collections/#{@collection_token}/availability?#{params}"

        barrier.async do
          response = client.get path, {'Authorization' => "Bearer #{@token}"}
          Console.logger.info "Batch number #{batch_number} of #{batches.size} response code: #{response.status}"
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
