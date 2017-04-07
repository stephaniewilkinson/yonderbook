require 'roda'
require 'tilt'
require 'nokogiri'
require 'oauth'
require 'http'
require 'uri'

class App < Roda
  CACHE = Roda::RodaCache.new

  BOOKMOOCH_URI = 'http://api.bookmooch.com'.freeze
  GOODREADS_URI = 'http://www.goodreads.com'.freeze
  APP_URI       = 'http://localhost:9292'.freeze

  use Rack::Session::Cookie, secret: ENV['GOODREADS_SECRET'], api_key: ENV['GOODREADS_API_KEY']
  plugin :render

  route do |r|
    session[:secret] = ENV['GOODREADS_SECRET']
    session[:api_key] = ENV['GOODREADS_API_KEY']

    r.root do
      consumer = OAuth::Consumer.new session[:api_key], session[:secret], site: GOODREADS_URI
      request_token = consumer.get_request_token oauth_callback: "#{APP_URI}/import"

      session[:request_token] = request_token
      @auth_url = request_token.authorize_url

      # GET /
      r.get do
        render 'welcome' # renders views/foo.erb inside views/layout.erb
      end
    end

    r.on 'import' do
      # GET /import
      r.get do
        access_token = session[:request_token].get_access_token
        response = access_token.get "#{GOODREADS_URI}/api/auth_user"
        xml = Nokogiri::XML response.body
        user_id = xml.xpath('//user').first.attributes.first[1].value
        params = URI.encode_www_form({shelf: 'to-read',
                                      per_page: '20',
                                      key: session[:api_key]})
        path = "/review/list/#{user_id}.xml?#{params}}"

        HTTP.persistent GOODREADS_URI do |http|
          doc = Nokogiri::XML http.get(path).body

          puts 'Counting pages...'
          @number_of_pages = doc.xpath('//books').first['numpages'].to_i
          puts "Found #{@number_of_pages} pages..."

          @isbnset = 1.upto(@number_of_pages).flat_map do |page|
            "Fetching page #{page}..."
            doc = Nokogiri::XML http.get("#{path}&page=#{page}").body

            doc.xpath('//isbn').children.map &:text
          end
        end

        CACHE[session[:session_id]] = @isbnset

        render 'import'
      end
    end

    r.on 'bookmooch' do
      # POST /bookmooch?username=foo&password=baz
      r.post do
        isbns = CACHE[session[:session_id]]
        auth = {user: r['username'], pass: r['password']}

        HTTP.basic_auth(auth).persistent(BOOKMOOCH_URI) do |http|
          isbns.each do |isbn|
            params = {asins: isbn, target: 'wishlist', action: 'add'}
            puts "Params: #{URI.encode_www_form params}"
            puts 'Adding to wishlist with bookmooch api...'
            response = http.get '/api/userbook', params: params
            puts response
          end
        end

        r.redirect '/bookmooch'
      end

      # GET /bookmooch
      r.get do
        render 'bookmooch'
      end
    end
  end
end

run App.freeze.app
