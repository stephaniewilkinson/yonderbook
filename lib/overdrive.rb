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

  Title = Data.define(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :availability_url, :no_isbn)

  def self.local_libraries zip_code
    task = Async do
      internet = Async::HTTP::Internet.new
      params = URI.encode_www_form query: zip_code, includePublicLibraries: true, includeSchoolLibraries: false
      response = internet.get "#{MAPBOX_URI}?#{params}"
      response.read
    ensure
      internet&.close
    end
    libraries = JSON.parse task.wait
    libraries.first(10).map { |l| [l['consortiumId'], l['consortiumName']] }
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
    add_id_and_url_to_books
    add_library_availability_to_books
    consolidate_duplicate_editions

    @books.map(&:first).sort_by { |book| [book.copies_available, book.copies_owned] }.reverse
  end

  def add_id_and_url_to_books
    expanded_books = []
    @books.each do |book, body|
      unless body
        expanded_books << [book, body]
        next
      end

      overdrive_editions = JSON.parse(body)['products']
      unless overdrive_editions && !overdrive_editions.empty?
        expanded_books << [book, body]
        next
      end
      overdrive_editions.each do |edition|
        book_copy = Title.new(
          title: book.title,
          author: book.author,
          image: edition.dig('images', 'cover300Wide', 'href') || book.image,
          copies_available: 0,
          copies_owned: 0,
          isbn: book.isbn,
          url: edition.dig('contentDetails', 0, 'href'),
          id: edition['id'],
          availability_url: nil,
          no_isbn: book.no_isbn
        )
        expanded_books << [book_copy, body]
      end
    end

    @books = expanded_books
  end

  def add_library_availability_to_books
    books_with_ids = @books.map(&:first).select(&:id)
    batches = books_with_ids.map(&:id).each_slice(25)

    responses = async_responses(batches).wait
    responses.each.with_index 1 do |(raw_body, status), _batch_number|
      body = JSON.parse raw_body
      next if status >= 400

      body['availability'].each do |result|
        book_index = @books.find_index { |title, _| title.id&.downcase == result['reserveId']&.downcase }
        next unless book_index

        book, book_body = @books[book_index]
        updated_book = book.with(copies_available: result['copiesAvailable'], copies_owned: result['copiesOwned'])
        @books[book_index] = [updated_book, book_body]
      end
    end
  end

  def consolidate_duplicate_editions
    books_by_key = {}
    @books.each do |book, body|
      key = book.isbn&.then { |isbn| isbn.empty? ? nil : isbn } || TitleNormalizer.normalize(book.title)
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
    candidate_has_availability = candidate_edition.copies_available.to_i.positive?
    current_has_availability = current_best_edition.copies_available.to_i.positive?
    return true if candidate_has_availability && !current_has_availability
    return false if !candidate_has_availability && current_has_availability

    candidate_edition.copies_available.to_i > current_best_edition.copies_available.to_i
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
      no_isbn: no_isbn
    )
  end

  def availability_path book
    if book[:isbn] && !book[:isbn].empty?
      params = URI.encode_www_form minimum: false, limit: 5, q: book[:isbn]
    else
      clean_title = TitleNormalizer.clean_for_search(book[:title])
      params = URI.encode_www_form minimum: false, limit: 5, q: "\"#{clean_title}\""
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
    response = client.get(availability_path(book), {'Authorization' => "Bearer #{@token}"})
    body = response.read
    response.close
    if missing_isbn?(book)
      body = validate_title_search_results(client, body, book[:author], book[:title])
      [title(book, no_isbn: true), body]
    else
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
      next unless author_matches?(overdrive_book, target_author)
      return overdrive_book if target_isbn && !target_isbn.empty? && isbn_matches_in_metadata?(client, overdrive_book, target_isbn)
      return overdrive_book if title_matches_exactly?(overdrive_book, target_title)
    end
    nil
  end

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
    metadata['formats']&.each do |format|
      next unless format['identifiers']

      format['identifiers'].each do |identifier|
        isbns << identifier['value'] if identifier['type'] == 'ISBN'
      end
    end
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
