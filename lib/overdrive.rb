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
    res['collectionToken'] # "v1L1BDAAAAA2R"
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

      book.id = products.dig 0, 'id'
      book.url = products.dig 0, 'contentDetails', 0, 'href'
    end
  end

  def add_library_availability_to_books
    hydra = Typhoeus::Hydra.new
    batches = @books.map(&:first).select(&:id).map(&:id).each_slice(25)

    puts "Batches of 25: #{batches.size} ..."

    requests = batches.map do |batch|
      uri = "https://api.overdrive.com/v2/collections/#{@collection_token}/availability?products=#{batch.join ','}"
      Typhoeus::Request.new uri, headers: {'Authorization' => "Bearer #{@token}"}
    end

    requests.each { |request| hydra.queue request }

    hydra.run

    requests.each do |request|
      body = JSON.parse request.response.body
      result = body['availability'].first
      book = @books.find { |title, _| title.id == result['reserveId'] }.first
      book.copies_available = result['copiesAvailable']
      book.copies_owned = result['copiesOwned']
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

      request = Typhoeus::Request.new availability_url, headers: {'Authorization' => "Bearer #{@token}"}
      hydra.queue request

      [title, request]
    end

    hydra.run

    books
  end
end
