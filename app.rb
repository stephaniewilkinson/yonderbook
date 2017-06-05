require 'roda'
require 'tilt'
require 'nokogiri'
require 'oauth'
require 'http'
require 'uri'
require 'sequel'
require 'pg'
require 'rollbar/middleware/rack'
require_relative 'tuple_space'

class App < Roda
  use Rollbar::Middleware::Rack
  plugin :render
  plugin :assets, :css => 'styles.css'
  compile_assets

  CACHE = ::TupleSpace.new

  BOOKMOOCH_URI = 'http://api.bookmooch.com'.freeze
  GOODREADS_URI = 'http://www.goodreads.com'.freeze
  APP_URI       = 'http://localhost:9292'.freeze

  use Rack::Session::Cookie, secret: ENV['GOODREADS_SECRET'], api_key: ENV['GOODREADS_API_KEY']

  route do |r|
    r.assets

    session[:secret] = ENV['GOODREADS_SECRET']
    session[:api_key] = ENV['GOODREADS_API_KEY']

    r.root do

      consumer = OAuth::Consumer.new session[:api_key], session[:secret], site: GOODREADS_URI
      request_token = consumer.get_request_token oauth_callback: "#{APP_URI}/import"

      session[:request_token] = request_token
      @auth_url = request_token.authorize_url

      # GET /
      r.get do
        view 'welcome' # renders views/foo.erb inside views/layout.erb
      end
    end

    r.on 'shelves' do
      # GET /import
      r.get do
        unless session[:goodreads_user_id]
          access_token = session[:request_token].get_access_token
          response = access_token.get "#{GOODREADS_URI}/api/auth_user"
          xml = Nokogiri::XML response.body
          user_id = xml.xpath('//user').first.attributes.first[1].value

          session[:goodreads_user_id] = user_id
        end

        params = URI.encode_www_form({user_id: session[:goodreads_user_id],
                                      key: session[:api_key]})

        path = "/shelf/list.xml?#{params}}"

        HTTP.persistent GOODREADS_URI do |http|
          doc = Nokogiri::XML http.get(path).body

          puts 'Getting shelves...'

          @shelf_names = doc.xpath('//shelves//name').children.to_a
          @shelf_books = doc.xpath('//shelves//book_count').children.to_a
        end

        @shelves = @shelf_names.zip(@shelf_books)
        view 'shelves'
      end

      error do |e|
      end

    end

    r.on 'books' do
      # POST /books
      r.post do

        session[:shelf_name] = r['shelf_name'].gsub('\"', '')

        r.redirect '/books'
      end

      # GET /books
      r.get do
        params = URI.encode_www_form({shelf: session[:shelf_name],
                                      per_page: '20',
                                      key: session[:api_key]})
        path = "/review/list/#{session[:goodreads_user_id]}.xml?#{params}}"

        HTTP.persistent GOODREADS_URI do |http|
          doc = Nokogiri::XML http.get(path).body

          puts 'Counting pages...'
          @number_of_pages = doc.xpath('//books').first['numpages'].to_i
          puts "Found #{@number_of_pages} pages..."

          @isbnset = 1.upto(@number_of_pages).flat_map do |page|
            "Fetching page #{page}..."
            doc = Nokogiri::XML http.get("#{path}&page=#{page}").body

            isbns = doc.xpath('//isbn').children.map &:text
            image_urls = doc.xpath('//image_url').children.map(&:text).grep_v /\A\n\z/

            isbns.zip(image_urls)
          end
        end

        CACHE["#{session[:session_id]}/isbns_and_image_urls"] = @isbnset

        view 'books'
      end
    end

    r.on 'bookmooch' do
      # POST /bookmooch?username=foo&password=baz
      r.post do
        isbns_and_image_urls = CACHE["#{session[:session_id]}/isbns_and_image_urls"]
        auth = {user: r['username'], pass: r['password']}
        @books_added = []
        @books_failed = []

        HTTP.basic_auth(auth).persistent(BOOKMOOCH_URI) do |http|
          isbns_and_image_urls.each do |isbn, image_url|
            params = {asins: isbn, target: 'wishlist', action: 'add'}
            puts "Params: #{URI.encode_www_form params}"
            puts 'Adding to wishlist with bookmooch api...'
            response = http.get '/api/userbook', params: params

            if response.body.to_s.strip == isbn
              @books_added << [isbn, image_url]
            else
              @books_failed << [isbn, image_url]
            end
          end
        end

        CACHE["#{session[:session_id]}/books_added"] = @books_added
        CACHE["#{session[:session_id]}/books_failed"] = @books_failed
        r.redirect '/bookmooch'
      end

      # GET /bookmooch
      r.get do
        @books_added = CACHE["#{session[:session_id]}/books_added"]
        @books_failed = CACHE["#{session[:session_id]}/books_failed"]
        view 'bookmooch'
      end
    end

    # GET /about
    r.on 'about' do
      r.get do
        view 'about'
      end
    end

  end
end
