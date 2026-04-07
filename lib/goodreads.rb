# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'async/http/internet'
require 'async/semaphore'
require 'nokogiri'
require 'oauth'
require 'uri'

module Goodreads
  Book = Struct.new :image_url, :isbn, :title
  API_KEY = ENV.fetch('GOODREADS_API_KEY')
  HOST = 'www.goodreads.com'
  BASE_URL = "https://#{HOST}".freeze
  GOODREADS_SECRET = ENV.fetch('GOODREADS_SECRET')
  BOOK_DETAILS = %w[isbn13 book/image_url title authors/author/name published rating date_added].freeze

  def self.gender_detector
    require 'gender_detector' unless defined?(GenderDetector)
    @gender_detector ||= GenderDetector.new
  end

  module_function

  def new_uri
    URI::HTTPS.build host: HOST
  end

  def fetch_shelves goodreads_user_id
    uri = new_uri
    uri.path = '/shelf/list.xml'
    uri.query = URI.encode_www_form user_id: goodreads_user_id, key: API_KEY

    Sync do
      response = Async::HTTP::Internet.get uri.to_s
      body = response.read
      response.close

      doc = Nokogiri::XML body
      shelf_names = doc.xpath('//shelves//name').children.to_a
      shelf_books = doc.xpath('//shelves//book_count').children.map { |x| x.to_s.to_i }

      shelf_names.zip shelf_books
    end
  end

  def get_books shelf_name, goodreads_user_id, access_token = nil
    path = "/review/list/#{goodreads_user_id}.xml?key=#{API_KEY}&v=2&shelf=#{shelf_name}&per_page=100"
    fetch_all_pages(path, access_token)
  end

  def fetch_all_pages path, access_token = nil
    Sync do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 4
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(4, parent: barrier)
      books = []

      # Fetch page 1 to determine total pages
      page1_path = "#{path}&page=1"
      headers = oauth_headers(page1_path, access_token)
      first_response = client.get(page1_path, headers)
      first_body = first_response.read
      first_response.close
      doc = Nokogiri::XML first_body
      total = doc.xpath('//reviews').first.attributes['total'].value.to_f
      number_of_pages = total.fdiv(100).ceil
      books.concat(extract_books_from_body(first_body))

      # Fetch remaining pages in parallel (capped at 4 concurrent)
      2.upto(number_of_pages).each do |page|
        semaphore.async do
          page_path = "#{path}&page=#{page}"
          response = client.get page_path, oauth_headers(page_path, access_token)
          body = response.read
          response.close
          books.concat(extract_books_from_body(body))
        end
      end

      barrier.wait
      books
    ensure
      barrier&.stop
      client&.close
    end
  end

  def oauth_headers path, access_token
    return [] unless access_token

    signed_req = access_token.consumer.create_signed_request(:get, path, access_token)
    [['authorization', signed_req['Authorization']]]
  end

  def extract_books_from_body body
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

  def fetch_user request_token, yonderbook_user_id
    access_token = request_token.get_access_token
    goodreads_token = access_token.token
    goodreads_secret = access_token.secret
    uri = new_uri
    uri.path = '/api/auth_user'
    response = access_token.get uri.to_s
    xml = Nokogiri::XML response.body
    user_node = xml.xpath('//user').first
    raise 'Goodreads API returned no user data' unless user_node

    user_id = user_node['id']
    raise 'Goodreads API response missing user id attribute' unless user_id

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
    count = books.group_by { |book| Goodreads.gender_detector.get_gender book[:title].split.first }.transform_values(&:size)
    [
      count.values_at(:female, :mostly_female).compact.sum,
      count.values_at(:male, :mostly_male).compact.sum,
      count.fetch(:andy, 0)
    ]
  end

  def plot_books_over_time books
    books.filter_map { |book| [book[:title], Integer(book[:published_year])] unless book[:published_year].to_s.empty? }
  end

  def rating_stats books
    books.group_by { |book| (book[:ratings] || book[:rating]).to_i }.transform_values(&:size)
  end

  def fetch_book_data isbn
    uri = new_uri
    uri.path = "/book/isbn/#{isbn}"
    uri.query = URI.encode_www_form(key: API_KEY)

    Sync do
      response = Async::HTTP::Internet.get uri.to_s

      case response.status
      when 200
        doc = Nokogiri::XML(response.read)
        title = doc.xpath('//title').text
        image_url = doc.xpath('//image_url').first&.text
        book = Book.new(title:, image_url:, isbn:)
        [:ok, book]
      else
        [:error, response.status]
      end
    ensure
      response&.close
    end
  end
end
