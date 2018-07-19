# frozen_string_literal: true

require 'oauth2'
require 'typhoeus'

class Overdrive
  API_URI    = 'https://api.overdrive.com/v1'
  MAPBOX_URI = 'https://www.overdrive.com/mapbox/find-libraries-by-location'
  OAUTH_URI  = 'https://oauth.overdrive.com'
  KEY        = ENV.fetch 'OVERDRIVE_KEY'
  SECRET     = ENV.fetch 'OVERDRIVE_SECRET'

  Title = Struct.new :title, \
                     :image, \
                     :copies_available, \
                     :copies_owned, \
                     :isbn, \
                     :url, \
                     :id, \
                     :availability_url, \
                     keyword_init: true

  class << self
    def local_libraries latlon
      response = HTTP.get MAPBOX_URI, params: {latLng: latlon, radius: 50}
      libraries = JSON.parse response.body

      libraries.first(10).map do |l|
        consortium_id = l['consortiumId']
        consortium_name = l['consortiumName']

        [consortium_id, consortium_name]
      end
    end
  end

  def initialize isbnset, consortium_id
    @isbnset = isbnset
    @token = token
    @collection_token = collection_token consortium_id, @token
    @books = create_books_with_overdrive_info
  end

  def token
    client = OAuth2::Client.new KEY, SECRET, token_url: '/token', site: OAUTH_URI
    client.client_credentials.get_token.token
  end

  # Four digit library id from user submitted form, fetching the library-specific endpoint
  def collection_token consortium_id, token
    library_uri = "#{API_URI}/libraries/#{consortium_id}"
    response = HTTP.auth("Bearer #{token}").get(library_uri)
    res = JSON.parse(response.body)
    res['collectionToken']
  end

  def fetch_titles_availability
    add_id_and_url_to_books
    add_library_availability_to_books

    @books.map(&:first).sort_by { |book| [book.copies_available, book.copies_owned] }.reverse
  end

  def add_id_and_url_to_books
    @books.each do |book, request|
      body = request.response.body
      next if body.empty?

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
    hydra = Typhoeus::Hydra.new
    books_with_ids = @books.map(&:first).select(&:id)
    batches = books_with_ids.map(&:id).each_slice(25)

    requests = batches.map do |batch|
      uri = "https://api.overdrive.com/v2/collections/#{@collection_token}/availability?products=#{batch.join ','}"
      Typhoeus::Request.new uri, headers: {Authorization: "Bearer #{@token}"}
    end

    requests.each { |request| hydra.queue request }

    hydra.run

    requests.each_with_index do |request, i|
      response = request.response
      body = JSON.parse response.body

      if response.code >= 500
        warn "skipping batch #{i.succ} of #{requests.size} ..."
        warn "status code: #{body['code']}"
        warn "body: #{body.inspect}"
        # {"errorCode"=>"InternalError", "message"=>"An unexpected error has occurred.", "token"=>"8b0c9f8c-2c5c-41f4-8b32-907f23baf111"}
        next
      end

      body['availability'].each do |result|
        book = @books.find { |title, _| title.id == result['reserveId'] }.first
        book.copies_available = result['copiesAvailable']
        book.copies_owned = result['copiesOwned']
      end
    end
  end

  def create_books_with_overdrive_info
    hydra = Typhoeus::Hydra.new

    books = @isbnset.map do |book|
      params = URI.encode_www_form minimum: false, q: "\"#{book[2]}\""
      availability_url = "#{Overdrive::API_URI}/collections/#{@collection_token}/products?#{params}"

      title = Title.new isbn: book[0],
                        image: book[1],
                        title: book[2],
                        copies_available: 0,
                        copies_owned: 0

      request = Typhoeus::Request.new availability_url, headers: {Authorization: "Bearer #{@token}"}
      hydra.queue request

      [title, request]
    end

    hydra.run

    books
  end
end
