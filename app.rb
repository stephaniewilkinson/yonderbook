# frozen_string_literal: true

require 'area'
require 'http'
require 'roda'
require 'rollbar/middleware/rack'
require 'tilt'
require 'zbar'
require_relative 'lib/db'
require_relative 'lib/goodreads'
require_relative 'lib/models'
require_relative 'lib/overdrive'
require_relative 'lib/tuple_space'

# the only class with class
class App < Roda
  use Rollbar::Middleware::Rack
  plugin :assets, css: 'styles.css'
  plugin :public, root: 'assets'
  plugin :flash
  plugin :render
  compile_assets

  CACHE = TupleSpace.new
  BOOKMOOCH_URI = 'http://api.bookmooch.com'

  use Rack::Session::Cookie, secret: Goodreads::SECRET, api_key: Goodreads::API_KEY

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
      request_token = Goodreads.new_request_token
      @auth_url = request_token.authorize_url

      cache_set request_token: request_token

      # route: GET /
      r.get do
        view 'welcome' # renders views/welcome.erb inside views/layout.erb
      end
    end

    r.on 'login' do
      r.get do
        r.redirect '/shelves/index'
      end
    end

    r.on 'shelves' do
      # route: GET /shelves
      r.get do
        if session[:goodreads_user_id]
          # @users.insert_conflict.insert(goodreads_user_id: session[:goodreads_user_id])
        else
          access_token = cache_get(:request_token).get_access_token
          user_id, _first_name = Goodreads.fetch_user access_token
          session[:goodreads_user_id] = user_id
          # @users.insert_conflict.insert(first_name: first_name, goodreads_user_id: user_id)
        end

        @shelves = Goodreads.fetch_shelves session[:goodreads_user_id]

        view 'shelves/index'
      end
    end

    # route: GET /shelves/to-read
    r.get 'bookshelves', String do |shelf_name|
      @shelf_name = shelf_name
      cache_set shelf_name: @shelf_name

      @isbnset = Goodreads.get_books @shelf_name, session[:goodreads_user_id]
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

        if isbns_and_image_urls
          HTTP.basic_auth(auth).persistent(BOOKMOOCH_URI) do |http|
            isbns_and_image_urls.each do |isbn, image_url, title|
              params = {asins: isbn, target: 'wishlist', action: 'add'}

              response = http.get '/api/userbook', params: params

              if response.body.to_s.strip == isbn
                @books_added << [title, image_url]
              else
                @books_failed << [title, image_url]
              end
            end
          end
        else
          r.redirect '/books'
        end

        cache_set books_added: @books_added, books_failed: @books_failed

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
          flash[:error] = 'please try a different zip code'
          r.redirect "bookshelves/#{cache_get :shelf_name}"
        end

        @local_libraries = Overdrive.local_libraries latlon

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

        unless @isbnset
          flash[:error] = 'Select a bookshelf first'
          r.redirect '/shelves/index'
        end

        # Making the API call to Library Availability endpoint
        titles = Overdrive.new(@isbnset, r['consortium']).fetch_titles_availability
        cache_set titles: titles

        r.redirect '/availability'
      end

      # route: GET /availability
      r.get do
        @titles = cache_get :titles
        view 'availability'
      end
    end

    r.on 'inventory' do
      # route: GET /inventory/new
      r.get 'new' do
        view 'inventory/new'
      end

      r.get Integer do |book_id|
        @book = @books.first(id: book_id)
        @user = @users.first(id: @book[:user_id])
        view 'inventory/show'
      end

      # route: POST /inventory/create?barcode_image="isbn.jpg"
      r.post 'create' do
        image = r[:barcode_image][:tempfile]
        barcodes = ZBar::Image.from_jpeg(image).process

        if barcodes.any?
          user = @users.first goodreads_user_id: session[:goodreads_user_id]
          barcodes.each do |barcode|
            isbn = barcode.data

            status, book = Goodreads.fetch_book_data isbn

            raise "#{status}: #{book}" unless status == :ok
            @books.insert isbn: isbn, user_id: user[:id], cover_image_url: book.image_url, title: book.title
          end
          r.redirect '/inventory/index'
        else
          flash[:error] = 'no barcode detected, please try again'
          r.redirect '/inventory/new'
        end
      end

      # route: GET /inventory
      r.get do
        view 'inventory/index'
      end
    end # end of /inventory

    r.on 'about' do
      # route: GET /about
      r.get do
        view 'about'
      end
    end

    r.on 'users' do
      # route: GET /users
      r.get do
        view 'users/index'
      end

      r.get 'show' do
        view 'users/show'
      end
    end
  end # end of routing
end
