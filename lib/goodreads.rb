# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'async/http/internet'
require 'gender_detector'
require 'nokogiri'
require 'oauth'
require 'uri'

module Goodreads
  Book = Struct.new :image_url, :isbn, :title, keyword_init: true
  API_KEY = ENV.fetch 'GOODREADS_API_KEY'
  GENDER_DETECTOR = GenderDetector.new
  HOST = 'www.goodreads.com'
  BASE_URL = "https://#{HOST}".freeze
  GOODREADS_SECRET = ENV.fetch 'GOODREADS_SECRET'
  BOOK_DETAILS = %w[isbn13 book/image_url title authors/author/name published rating date_added].freeze

  module_function

  def new_uri
    URI::HTTPS.build host: HOST
  end

  def fetch_shelves goodreads_user_id
    uri = new_uri
    uri.path = '/shelf/list.xml'
    uri.query = URI.encode_www_form user_id: goodreads_user_id, key: API_KEY

    task = Async do
      internet = Async::HTTP::Internet.new
      response = internet.get uri.to_s
      response.read
    ensure
      internet&.close
    end

    doc = Nokogiri::XML task.wait
    shelf_names = doc.xpath('//shelves//name').children.to_a
    shelf_books = doc.xpath('//shelves//book_count').children.map { |x| x.to_s.to_i }

    shelf_names.zip shelf_books
  end

  def get_books shelf_name, goodreads_user_id, access_token
    path = "/review/list/#{goodreads_user_id}.xml?key=#{API_KEY}&v=2&shelf=#{shelf_name}&per_page=100"
    uri = "#{BASE_URL}#{path}"
    response = access_token.get(uri)
    doc = Nokogiri::XML response.body
    number_of_pages = doc.xpath('//reviews').first.attributes['total'].value.to_f.fdiv(100).ceil
    bodies = get_requests path, number_of_pages, access_token
    get_book_details bodies
  end

  def get_requests path, number_of_pages, access_token
    get_bodies = Async do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new

      if client.head(path).status == 200
        bodies = []

        1.upto(number_of_pages).each do |page|
          barrier.async do
            response = client.get "#{path}&page=#{page}"
            bodies << response.read
          ensure
            response&.close
          end
        end

        begin
          barrier.wait
        ensure
          barrier&.stop
        end

        bodies
      else
        1.upto(number_of_pages).map do |page|
          access_token.get("#{BASE_URL}#{path}&page=#{page}").response.body
        end
      end
    ensure
      client&.close
    end

    get_bodies.wait
  end

  def get_book_details bodies
    bodies.flat_map do |body|
      doc = Nokogiri::XML body
      data = BOOK_DETAILS.map { |path| doc.xpath("//#{path}").map(&:text).grep_v(/\A\n\z/) }.transpose

      data.map do |book_data|
        isbn, image_url, title, author, published_year, rating, date_added = book_data
        {
          isbn:,
          image_url:,
          title:,
          author:,
          published_year:,
          ratings: rating,
          date_added:
        }
      end
    end
  end

  def fetch_user request_token, yonderbook_user_id
    access_token = request_token.get_access_token
    goodreads_token = access_token.token
    goodreads_secret = access_token.secret
    uri = new_uri
    uri.path = '/api/auth_user'
    response = access_token.get uri.to_s
    xml = Nokogiri::XML response.body
    user_id = xml.xpath('//user').first.attributes.first[1].value
    xml.xpath('//user').first.children[1].children.text

    # Save Goodreads connection to database
    save_goodreads_connection(yonderbook_user_id, user_id, goodreads_token, goodreads_secret)

    [user_id, goodreads_token, goodreads_secret]
  end

  def save_goodreads_connection yonderbook_user_id, user_id, token, secret
    connection = GoodreadsConnection[user_id: yonderbook_user_id, goodreads_user_id: user_id]
    attrs = {access_token: token, access_token_secret: secret, connected_at: Time.now}
    connection ? connection.update(attrs) : GoodreadsConnection.create(attrs.merge(user_id: yonderbook_user_id, goodreads_user_id: user_id))
  end

  def get_gender books
    count = books.group_by { |book| GENDER_DETECTOR.get_gender book.fetch(:title).split.first }.transform_values(&:size)
    [
      count.values_at(:female, :mostly_female).compact.sum,
      count.values_at(:male, :mostly_male).compact.sum,
      count.fetch(:andy, 0)
    ]
  end

  def plot_books_over_time books
    books.filter_map { |book| [book[:title], Integer(book[:published_year])] unless book[:published_year].empty? }
  end

  def rating_stats books
    books.group_by { |book| (book[:ratings] || book[:rating]).to_i }.transform_values(&:size)
  end

  def fetch_book_data isbn
    uri = new_uri
    uri.path = "/book/isbn/#{isbn}"
    uri.query = URI.encode_www_form(key: API_KEY)

    task = Async do
      response = internet.get uri.to_s
      response_code = response.status

      case response_code
      when 200
        doc = Nokogiri::XML(response.read)
        title = doc.xpath('//title').text
        image_url = doc.xpath('//image_url').first.text
        book = Book.new(title:, image_url:, isbn:)

        [:ok, book]
      else
        [:error, response_code]
      end
    ensure
      internet&.close
    end

    task.wait
  end
end
