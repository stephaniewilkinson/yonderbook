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
                     :isbn, \
                     :availability_url, \
                     :versions, \
                     keyword_init: true

  Version = Struct.new :id, \
                      :copies_available, \
                      :copies_owned, \
                      :url, \
                      :format, \
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

    @books.map(&:first)
  end

  def add_id_and_url_to_books
    @books.each do |book, request|
      body = request.response.body
      next if body.empty?

      products = JSON.parse(body)['products']
      next unless products

      book.image = products.dig(0, 'images', 'cover300Wide', 'href')

      products.each do |product|
        version = Version.new id: product.dig('id'),
                            url: product.dig('contentDetails', 0, 'href'),
                            format: product.dig('mediaType')
        book.versions << version
      end

    end
  end

  def add_library_availability_to_books
    # TODO: expand this section to include links and ids for other book formats
    hydra = Typhoeus::Hydra.new
    books_with_ids = @books.map(&:first).map(&:versions).flatten.map(&:id)
    batches = books_with_ids.flatten.each_slice(25)

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
        book = @books.find { |book, _| book.versions.map(&:id).include? result['reserveId'] }.first
        version = book.versions.find { |v| v.id.include? result['reserveId'] }
        version.copies_available = result['copiesAvailable']
        version.copies_owned = result['copiesOwned']
      end
    end
  end

  def create_books_with_overdrive_info
    hydra = Typhoeus::Hydra.new

    books = @isbnset.map do |book|
      params = URI.encode_www_form minimum: false, q: "\"#{book[2]}\""
      availability_url = "#{Overdrive::API_URI}/collections/#{@collection_token}/products?#{params}"

      title = Title.new isbn: book[0],
                        title: book[2],
                        image: book[1],
                        availability_url: [],
                        versions: []

      request = Typhoeus::Request.new availability_url, headers: {Authorization: "Bearer #{@token}"}
      hydra.queue request

      [title, request]
    end

    hydra.run

    books
  end
end
