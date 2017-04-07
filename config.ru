require 'roda'
require 'tilt'
require 'nokogiri'
require 'oauth'
require 'http'
require 'uri'
require 'yaml/dbm'
require 'pry'

class App < Roda
  DB = YAML::DBM.new '.bookmooch.db'
  BOOKMOOCH_URI = 'http://api.bookmooch.com/api/userbook'.freeze
  GOODREADS_URI = 'http://www.goodreads.com'.freeze
  GOODREADS_SHELF_URI = "#{GOODREADS_URI}/review/list".freeze
  GOODREADS_ACCESS_TOKEN_URI = "#{GOODREADS_URI}/api/auth_user".freeze

  use Rack::Session::Cookie, secret: ENV['GOODREADS_SECRET'], api_key: ENV['GOODREADS_API_KEY']
  plugin :render
  route do |r|
    session[:secret] = ENV['GOODREADS_SECRET']
    session[:api_key] = ENV['GOODREADS_API_KEY']

    r.root do
      consumer = OAuth::Consumer.new session[:api_key], session[:secret], site: GOODREADS_URI
      request_token = consumer.get_request_token oauth_callback: 'http://localhost:9292/bar'

      session[:request_token] = request_token
      @auth_url = request_token.authorize_url

      # GET /
      r.get do
        render 'welcome' # renders views/foo.erb inside views/layout.erb
      end
    end

    # GET /bar
    r.get 'bar' do
      access_token = session[:request_token].get_access_token
      response = access_token.get GOODREADS_ACCESS_TOKEN_URI
      xml = Nokogiri::XML response.body
      user_id = xml.xpath('//user').first.attributes.first[1].value
      params = URI.encode_www_form({shelf: 'to-read',
                                    per_page: '20',
                                    key: session[:api_key]})
      uri = "#{GOODREADS_SHELF_URI}/#{user_id}.xml?#{params}}"

      begin
        # create HTTP client with persistent connection to goodreads
        http = HTTP.persistent uri

        # issue multiple requests using same connection:
        doc = Nokogiri::XML http.get(uri).body

        puts 'Counting pages...'
        @number_of_pages = doc.xpath('//books').first['numpages'].to_i
        puts "Found #{@number_of_pages} pages..."

        @isbnset = 1.upto(@number_of_pages).flat_map do |page|
          "Fetching page #{page}..."
          doc = Nokogiri::XML http.get("#{uri}&page=#{page}").body

          doc.xpath('//isbn').children
        end
        DB['isbnset'] = @isbnset
        binding.pry
      ensure
        # close underlying connection when you don't need it anymore
        http.close if http
      end

      render 'bar'
    end

    # POST /bookmooch?username=foo&password=baz
    r.post 'bookmooch' do
      begin
        client = HTTP.persistent(BOOKMOOCH_URI).basic_auth user: r['username'], pass: r['password']

        DB['isbnset'].each do |isbn|
          params = {asins: isbn, target: 'wishlist', action: 'add'}

          puts "Params: #{URI.encode_www_form params}"
          puts "Adding to wishlist with bookmooch api..."
          client.get url, params: params
        end
      ensure
        client.close if client
      end
    end
  end
end

run App.freeze.app
