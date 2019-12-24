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
require_relative 'db'

module Goodreads
  Book = Struct.new :image_url, :isbn, :title, keyword_init: true
  API_KEY = ENV.fetch 'GOODREADS_API_KEY'
  GENDER_DETECTOR = GenderDetector.new
  HOST = 'www.goodreads.com'
  GOODREADS_SECRET = ENV.fetch 'GOODREADS_SECRET'
  USERS = DB[:users]
  BOOK_DETAILS = %w[isbn book/image_url title authors/author/name published rating].freeze

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
    shelf_books = doc.xpath('//shelves//book_count').children.map(&:to_s).map(&:to_i)

    shelf_names.zip shelf_books
  end

  def get_books shelf_name, goodreads_user_id, access_token
    uri = "https://www.goodreads.com/review/list/#{goodreads_user_id}.xml?key=#{API_KEY}&v=2&shelf=#{shelf_name}&per_page=200"
    response = access_token.get(uri)
    doc = Nokogiri::XML response.body
    number_of_pages = doc.xpath('//reviews').first.attributes['total'].value.to_f.fdiv(200).ceil
    bodies = get_requests uri, number_of_pages, access_token
    get_book_details bodies
  end

  def get_requests uri, number_of_pages, access_token
    get_bodies = Async do
      endpoint = Async::HTTP::Endpoint.parse(uri)
      client = Async::HTTP::Client.new(endpoint)
      barrier = Async::Barrier.new

      if client.head(uri).status == 200
        bodies = []

        1.upto(number_of_pages).each do |page|
          barrier.async do
            response = client.get "&page=#{page}"
            bodies << response.read
          end
        end

        barrier.wait

        bodies
      else
        1.upto(number_of_pages).map do |page|
          access_token.get("#{uri}&page=#{page}").response.body
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

      data.map do |isbn, image_url, title, author, published_year, rating|
        {
          isbn: isbn,
          image_url: image_url,
          title: title,
          author: author,
          published_year: published_year,
          ratings: rating
        }
      end
    end
  end

  def fetch_user request_token
    access_token = request_token.get_access_token
    uri = new_uri
    uri.path = '/api/auth_user'
    response = access_token.get uri.to_s
    xml = Nokogiri::XML response.body
    user_id = xml.xpath('//user').first.attributes.first[1].value
    name = xml.xpath('//user').first.children[1].children.text

    if USERS.first(goodreads_user_id: user_id)
      USERS.where(goodreads_user_id: user_id).update(access_token: access_token.token, access_token_secret: access_token.secret)
    else
      USERS.insert(first_name: name, goodreads_user_id: user_id, access_token: access_token.token, access_token_secret: access_token.secret)
    end
    user_id
  end

  def get_gender books
    grouped = books.group_by do |book|
      GENDER_DETECTOR.get_gender book.fetch(:title).split.first
    end
    count = grouped.transform_values(&:size)
    mostly_female = count.values_at(:female, :mostly_female).compact.sum
    mostly_male = count.values_at(:male, :mostly_male).compact.sum
    androgynous = count.fetch :andy, 0

    [mostly_female, mostly_male, androgynous]
  end

  def plot_books_over_time books
    books.map { |book| [book[:title], Integer(book[:published_year])] unless book[:published_year].empty? }.compact
  end

  def rating_stats books
    books.group_by { |book| book[:rating].to_i }.transform_values(&:size)
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
        book = Book.new title: title, image_url: image_url, isbn: isbn

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
