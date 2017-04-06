require 'roda'
require 'tilt'
require 'nokogiri'
require 'open-uri'
require 'oauth'
require 'pry'

class App < Roda
  use Rack::Session::Cookie, secret: ENV['SECRET'], api_key: ENV['API_KEY']
  plugin :render
  route do |r|
    session[:secret] = ENV['SECRET']
    session[:api_key] = ENV['API_KEY']
    r.root do
      api_key = session[:api_key]
      secret = session[:secret]
      consumer = OAuth::Consumer.new api_key, secret, site: 'http://www.goodreads.com'
      request_token = consumer.get_request_token oauth_callback: 'http://localhost:9292/bar'
      @auth_url = request_token.authorize_url
      session[:request_token] = request_token

      r.get do
        render('welcome') # renders views/foo.erb inside views/layout.erb
      end
    end
    r.get 'bar' do
      request_token = session[:request_token]
      access_token = request_token.get_access_token
      res = access_token.get "https://www.goodreads.com/api/auth_user"
      doc = Nokogiri::XML res.body
      user = doc.xpath "//user"
      user_id = user.first.attributes.first[1].value

      uri = 'https://www.goodreads.com/review/list/' + user_id + '.xml?shelf=toread&key=' + session[:api_key]
      doc = Nokogiri::XML open uri
      @isbnset = (doc.xpath '//isbn').children
      @numpages = (doc.xpath "//books").first["numpages"].to_i
      # range = (2..numpages).to_a
      # if numpages > 2
      #   for i in range.to_a do
      #     doc = Nokogiri::XML open (uri + "&page=" + i.to_s)
      #     @isbns = (doc.xpath '//isbn').children
      #     @isbnset = @isbnset + @isbns
      #   end
      # end

      render 'bar'
    end

    r.post do
      session[:username] = username
      session[:password] = password
      render 'welcome'
    end
    # POST /hello request
    r.post do
      puts "Someone said #{@greeting}!"
      r.redirect
    end



  end
end

run App.freeze.app
