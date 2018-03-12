# frozen_string_literal: true

require 'area'
require 'http'
require 'nokogiri'
require 'oauth'
require 'oauth2'
require 'pry'
require 'roda'
require 'rollbar/middleware/rack'
require 'tilt'
require 'uri'
require 'zbar'
require_relative 'lib/db'
require_relative 'lib/models'
require_relative 'lib/goodreads'
require_relative 'lib/tuple_space'

class App < Roda
  use Rollbar::Middleware::Rack
  plugin :assets, css: 'styles.css'
  plugin :public, root: 'assets'
  plugin :render
  compile_assets

  CACHE                 = ::TupleSpace.new

  BOOKMOOCH_URI         = 'http://api.bookmooch.com'
  GOODREADS_URI         = 'https://www.goodreads.com'
  OVERDRIVE_API_URI     = 'https://api.overdrive.com/v1'
  OVERDRIVE_MAPBOX_URI  = 'https://www.overdrive.com/mapbox/find-libraries-by-location'
  OVERDRIVE_OAUTH_URI   = 'https://oauth.overdrive.com'

  GOODREADS_API_KEY     = ENV.fetch 'GOODREADS_API_KEY'
  GOODREADS_SECRET      = ENV.fetch 'GOODREADS_SECRET'
  OVERDRIVE_KEY         = ENV.fetch 'OVERDRIVE_KEY'
  OVERDRIVE_SECRET      = ENV.fetch 'OVERDRIVE_SECRET'

  use Rack::Session::Cookie, secret: GOODREADS_SECRET, api_key: GOODREADS_API_KEY

  def cache_set **pairs
    pairs.each do |key, value|
      CACHE["#{session[:session_id]}/#{key}"] = value
    end
  end

  def cache_get key
    CACHE["#{session[:session_id]}/#{key}"]
  end

  route do |r|
    r.public
    r.assets

    @books = DB[:books]
    @users = DB[:users]

    r.root do
      consumer = OAuth::Consumer.new GOODREADS_API_KEY, GOODREADS_SECRET, site: GOODREADS_URI
      request_token = consumer.get_request_token
      @auth_url = request_token.authorize_url

      cache_set request_token: request_token

      # route: GET /
      r.get do
        view 'welcome' # renders views/welcome.erb inside views/layout.erb
      end
    end

    r.on 'shelves' do
      # route: GET /shelves
      r.get do
        if session[:goodreads_user_id]
          @users.insert_conflict.insert(goodreads_user_id: session[:goodreads_user_id])
        else
          access_token = cache_get(:request_token).get_access_token
          response = access_token.get "#{GOODREADS_URI}/api/auth_user"
          xml = Nokogiri::XML response.body
          user_id = xml.xpath('//user').first.attributes.first[1].value
          first_name = xml.xpath('//user').first.children[1].children.text

          @users.insert_conflict.insert(first_name: first_name, goodreads_user_id: user_id)

          session[:goodreads_user_id] = user_id
        end

        params = URI.encode_www_form(
          user_id: session[:goodreads_user_id],
          key: GOODREADS_API_KEY
        )

        path = "/shelf/list.xml?#{params}}"

        HTTP.persistent GOODREADS_URI do |http|
          doc = Nokogiri::XML http.get(path).body

          @shelf_names = doc.xpath('//shelves//name').children.to_a
          @shelf_books = doc.xpath('//shelves//book_count').children.to_a
        end

        @shelves = @shelf_names.zip(@shelf_books)
        view 'shelves/index'
      end
    end

    # route: GET /shelves/to-read
    r.get 'bookshelves', String do |shelf_name|
      @shelf_name = shelf_name
      params = URI.encode_www_form(
        shelf: @shelf_name,
        per_page: '20',
        key: GOODREADS_API_KEY
      )
      path = "/review/list/#{session[:goodreads_user_id]}.xml?#{params}}"

      HTTP.persistent GOODREADS_URI do |http|
        doc = Nokogiri::XML http.get(path).body

        @number_of_pages = doc.xpath('//books').first['numpages'].to_i

        @isbnset = 1.upto(@number_of_pages).flat_map do |page|
          "Fetching page #{page}..."
          doc = Nokogiri::XML http.get("#{path}&page=#{page}").body
          isbns = doc.xpath('//isbn').children.map &:text
          image_urls = doc.xpath('//book/image_url').children.map(&:text).grep_v /\A\n\z/
          titles = doc.xpath('//title').children.map &:text
          isbns.zip(image_urls, titles)
        end
      end

      cache_set isbns_and_image_urls: @isbnset
      @invalidzip = r.params['invalidzip']

      view 'bookshelves'
    end

    r.on 'bookmooch' do
      # route: POST /bookmooch?username=foo&password=baz
      r.post do
        isbns_and_image_urls = cache_get :isbns_and_image_urls

        unless r['username'] == 'susanb'
          auth = {user: r['username'], pass: r['password']}
        end
        @books_added = []
        @books_failed = []

        HTTP.basic_auth(auth).persistent(BOOKMOOCH_URI) do |http|
          if isbns_and_image_urls
            isbns_and_image_urls.each do |isbn, image_url, title|
              params = {asins: isbn, target: 'wishlist', action: 'add'}

              response = http.get '/api/userbook', params: params

              if response.body.to_s.strip == isbn
                @books_added << [title, image_url]
              else
                @books_failed << [title, image_url]
              end
            end
          else
            r.redirect '/books'
          end
        end

        cache_set books_added: @books_added
        cache_set books_failed: @books_failed

        r.redirect '/bookmooch'
      end

      # route: GET /bookmooch
      r.get do
        @books_added = cache_get :books_added
        @books_failed = cache_get :books_failed

        view 'bookmooch'
      end
    end

    r.on 'library' do
      # route: POST /library?zipcode=90029
      r.post do
        zip = r['zipcode']

        if zip.to_latlon
          latlon = r['zipcode'].to_latlon.delete ' '
        else
          r.redirect "books?invalidzip=#{zip}"
        end

        response = HTTP.get OVERDRIVE_MAPBOX_URI, params: {latLng: latlon, radius: 50}
        libraries = JSON.parse response.body

        @local_libraries = libraries.first(10).map do |l|
          consortium_id = l['consortiumId']
          consortium_name = l['consortiumName']

          [consortium_id, consortium_name]
        end

        cache_set libraries: @local_libraries
        r.redirect '/library'
      end

      # route: GET /library
      r.get do
        @local_libraries = cache_get :libraries
        view 'library'
      end
    end

    ##
    # FEATURE IN PROGRESS \o/
    r.on 'availability' do
      # route: POST /availability?consortium=1047
      r.post do
        # Pulling book info from the cache
        @isbnset = cache_get :isbns_and_image_urls

        @titles = @isbnset.map { |book| URI.encode(book[2]) }

        # Fetching auth token from overdrive
        client = OAuth2::Client.new(OVERDRIVE_KEY, OVERDRIVE_SECRET, token_url: '/token', site: OVERDRIVE_OAUTH_URI)
        token_request = client.client_credentials.get_token
        token = token_request.token

        # Four digit library id from user submitted form
        consortium_id = r['consortium'].delete('\"') # 1047

        # Fetching the library-specific endpoint
        library_uri = "#{OVERDRIVE_API_URI}/libraries/#{consortium_id}"
        response = HTTP.auth("Bearer #{token}").get(library_uri)
        res = JSON.parse(response.body)
        collectionToken = res['collectionToken'] # "v1L1BDAAAAA2R"

        # The URL that I need to provide to the user to actually click on and
        # visit so that they can check out the book is in this format:
        # https://lapl.overdrive.com/media/c8a88fb7-c369-454c-b113-9703b1816d57
        # where the id is at the end of the url
        # the only thing i need to figure out is the subdomain at the beginning, AKA 'lapl'
        # because the book id stays the same

        # Making the API call to Library Availability endpoint
        availability_uri = "#{OVERDRIVE_API_URI}/collections/#{collectionToken}/products?q=#{@titles.first}"
        response = HTTP.auth("Bearer #{token}").get(availability_uri)
        res = JSON.parse(response.body)
        book_availibility_url = res['products'].first['links'].assoc('availability').last['href']

        # Checking if the book is available
        response = HTTP.auth("Bearer #{token}").get(book_availibility_url)
        res = JSON.parse(response.body)
        copiesOwned = res['copiesOwned']
        copiesAvailable = res['copiesAvailable']

        r.redirect '/availability'
      end

      # route: GET /availability
      r.get do
        view 'availability'
      end
    end

    r.on 'inventory' do
      # route: GET /inventory/new
      r.get 'new' do
        view 'inventory/new'
      end

      # route: POST /inventory/create?barcode_image="isbn.jpg"
      r.post 'create' do
        image = r[:barcode_image][:tempfile]
        isbns = ZBar::Image.from_jpeg(image).process

        if isbns.any?
          user = @users.first goodreads_user_id: session[:goodreads_user_id]
          isbns.each do |isbn|
            @books.insert isbn: isbn.data, user_id: user[:id]
          end
          r.redirect '/inventory/index'
        else
          # TODO: add error message 'unable to read barcode'
          r.redirect '/inventory/new'
        end
      end

      # route: GET /inventory/index
      r.get 'index' do
        view 'inventory/index'
      end
    end # end of /inventory

    r.on 'about' do
      # route: GET /about
      r.get do
        view 'about'
      end
    end
  end # end of routing
end
