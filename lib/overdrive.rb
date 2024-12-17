# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'async/http/internet'
require 'async/semaphore'
require 'oauth2'
require 'uri'

class Overdrive
  BASE_URL     = 'https://api.overdrive.com'
  API_URI      = "#{BASE_URL}/v1".freeze
  MAPBOX_URI   = 'https://www.overdrive.com/mapbox/find-libraries-by-query'
  OAUTH_URI    = 'https://oauth.overdrive.com'
  KEY          = ENV.fetch 'OVERDRIVE_KEY'
  SECRET       = ENV.fetch 'OVERDRIVE_SECRET'

  Title = Struct.new :title, :image, :copies_available, :copies_owned, :isbn, :url, :id, :availability_url, keyword_init: true

  def self.local_libraries zip_code
    # here is teh url that overdrive uses to search
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
    # they have changed the JSON payload here so it only responds with the 'consortium' and the libraries are nested
    # maybe this is ok though
    libraries.first(10).map do |l|
      consortium_id = l['consortiumId']
      consortium_name = l['consortiumName']

      [consortium_id, consortium_name]
    end
  end

  def initialize book_info, consortium_id
    @book_info = book_info
    @token = token

    @collection_token = collection_token consortium_id, @token
    @books = async_books_with_overdrive_info.wait
  end

  def token
    client = OAuth2::Client.new KEY, SECRET, token_url: '/token', site: OAUTH_URI
    client.client_credentials.get_token.token
  end

  # Four digit library id from user submitted form, fetching the library-specific endpoint
  def collection_token consortium_id, token
    library_uri = "#{API_URI}/libraries/#{consortium_id}"

    task = Async do
      internet = Async::HTTP::Internet.new
      response = internet.get(library_uri, {'Authorization' => "Bearer #{token}"})
      response.read
    ensure
      internet&.close
    end

    body = JSON.parse task.wait
    body['collectionToken']
  end

  def fetch_titles_availability
    add_id_and_url_to_books
    add_library_availability_to_books

    @books.map(&:first).sort_by { |book| [book.copies_available, book.copies_owned] }.reverse
  end

  def add_id_and_url_to_books
    @books.each do |book, body|
      next unless body

      products = JSON.parse(body)['products']
      next unless products

      # This part is fine, both of these variables are the only id and url there is at this point
      # looking for other formats needs to happen earlier in the process than Here
      # by the time we get here, we are only dealing with one isbn and format
      book.id = products.dig 0, 'id'
      book.url = products.dig 0, 'contentDetails', 0, 'href'
      book.image = (products.dig 0, 'images', 'cover300Wide', 'href')
    end
  end

  def add_library_availability_to_books
    # TODO: expand this section to include links and ids for other book formats
    books_with_ids = @books.map(&:first).select(&:id)
    batches = books_with_ids.map(&:id).each_slice(25)

    responses = async_responses(batches).wait
    responses.each.with_index 1 do |(raw_body, status), batch_number|
      body = JSON.parse raw_body

      if status >= 400
        warn "skipping batch #{batch_number} of #{responses.size} ..."
        warn "status code: #{status}"
        warn "body: #{body.inspect}"
        # {"errorCode"=>"InternalError", "message"=>"An unexpected error has occurred.", "token"=>"8b0c9f8c-2c5c-41f4-8b32-907f23baf111"}
        next
      end

      body['availability'].each do |result|
        # fail occurs here

        book = @books.find do |title, _|
          title.id = result['reserveId']
        end.first
        book.copies_available = result['copiesAvailable']
        book.copies_owned = result['copiesOwned']
      end
    end
  end

  private

  def title book
    Title.new(isbn: book[:isbn], image: book[:image_url], title: book[:title], copies_available: 0, copies_owned: 0)
  end

  def availability_path book
    title = "\"#{book.fetch :title}\""
    params = URI.encode_www_form minimum: false, limit: 1, q: title

    "/v1/collections/#{@collection_token}/products?#{params}"
  end

  def async_books_with_overdrive_info
    Async do |task|
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 16
      barrier = Async::Barrier.new

      task.with_timeout 25 do
        books = []

        @book_info.each.with_index 1 do |book, book_number|
          barrier.async do
            response = client.get(availability_path(book), {'Authorization' => "Bearer #{@token}"})
            body = response.read

            warn "Book number #{book_number} of #{@book_info.size} response code: #{response.status}"

            books << [title(book), body]
          end
        end

        barrier.wait

        books
      rescue Async::TimeoutError
        books
      end
    ensure
      client&.close
    end
  end

  def async_responses batches
    Async do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 16
      barrier = Async::Barrier.new

      responses = []

      batches.each.with_index 1 do |batch, batch_number|
        params = URI.encode_www_form products: batch.join(',')
        path = "/v2/collections/#{@collection_token}/availability?#{params}"

        barrier.async do
          response = client.get path, {'Authorization' => "Bearer #{@token}"}
          Console.logger.info "Batch number #{batch_number} of #{batches.size} response code: #{response.status}"
          responses << [response.read, response.status]
        end
      end

      barrier.wait

      responses
    ensure
      client&.close
    end
  end
end
