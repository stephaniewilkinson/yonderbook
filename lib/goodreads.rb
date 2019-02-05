# frozen_string_literal: true

require 'gender_detector'
require 'nokogiri'
require 'oauth'
require 'typhoeus'
require 'uri'
require_relative 'db'

module Goodreads
  Book = Struct.new :image_url, :isbn, :title, keyword_init: true
  API_KEY = ENV.fetch 'GOODREADS_API_KEY'
  GENDER_DETECTOR = GenderDetector.new
  HOST = 'www.goodreads.com'
  GOODREADS_SECRET = ENV.fetch 'GOODREADS_SECRET'
  @users = DB[:users]

  module_function

  def new_uri
    URI::HTTPS.build host: HOST
  end

  def fetch_shelves goodreads_user_id
    uri = new_uri
    uri.path = '/shelf/list.xml'
    uri.query = URI.encode_www_form user_id: goodreads_user_id, key: API_KEY

    doc = Nokogiri::XML Typhoeus.get(uri).body
    shelf_names = doc.xpath('//shelves//name').children.to_a
    shelf_books = doc.xpath('//shelves//book_count').children.map(&:to_s).map(&:to_i)

    shelf_names.zip shelf_books
  end

  def get_books shelf_name, goodreads_user_id, access_token
    uri = "https://www.goodreads.com/review/list/#{goodreads_user_id}.xml?key=#{API_KEY}&v=2&shelf=#{shelf_name}&per_page=200"
    response = access_token.get(uri)
    doc = Nokogiri::XML response.body
    number_of_pages = doc.xpath('//reviews').first.attributes['total'].value.to_f.fdiv(200).ceil
    requests = get_requests uri, number_of_pages, access_token
    get_book_details requests
  end

  def private_profile? shelf_name, goodreads_user_id
    uri = new_uri
    uri.path = "/review/list/#{goodreads_user_id}.xml"
    uri.query = URI.encode_www_form shelf: shelf_name, key: API_KEY

    Typhoeus.head(uri).code == 403
  end

  def get_requests uri, number_of_pages, access_token
    if Typhoeus.head(uri).code == 200
      hydra = Typhoeus::Hydra.new

      requests = 1.upto(number_of_pages).map do |page|
        request = Typhoeus::Request.new "#{uri}&page=#{page}"
        hydra.queue request
        request
      end

      hydra.run
      requests
    else
      1.upto(number_of_pages).map do |page|
        access_token.get("#{uri}&page=#{page}")
      end
    end
  end

  def get_book_details requests
    # TODO: make this a hash instead of array
    requests.flat_map do |request|
      doc = Nokogiri::XML request.response.body

      isbns = doc.xpath('//isbn').map { |node| node.children.text }
      image_urls = doc.xpath('//book/image_url').children.map(&:text).grep_v(/\A\n\z/)
      titles = doc.xpath('//title').children.map(&:text)
      authors = doc.xpath('//authors/author/name').children.map(&:text)
      published_years = doc.xpath('//published').children.map(&:text)

      isbns.zip image_urls, titles, authors, published_years
    end
  end

  def fetch_user access_token
    uri = new_uri
    uri.path = '/api/auth_user'
    response = access_token.get uri.to_s
    xml = Nokogiri::XML response.body
    user_id = xml.xpath('//user').first.attributes.first[1].value
    first_name = xml.xpath('//user').first.children[1].children.text

    @users.insert(first_name: first_name, goodreads_user_id: user_id) unless @users.first(goodreads_user_id: user_id)

    [user_id, first_name]
  end

  def get_gender isbnset
    grouped = isbnset.group_by do |_, _, _, name|
      GENDER_DETECTOR.get_gender name.split.first
    end
    count = grouped.transform_values(&:size)
    mostly_female = count.values_at(:female, :mostly_female).compact.sum
    mostly_male = count.values_at(:male, :mostly_male).compact.sum
    androgynous = count.fetch :andy, 0

    [mostly_female, mostly_male, androgynous]
  end

  def plot_books_over_time isbnset
    isbnset.map { |_, _, title, _, year| [title, Integer(year)] if year }.compact
  end

  def fetch_book_data isbn
    uri = new_uri
    uri.path = "/book/isbn/#{isbn}"
    response = Typhoeus.get uri, params: {key: API_KEY}
    case response.code
    when 200
      doc = Nokogiri::XML(response.body)
      title = doc.xpath('//title').text
      image_url = doc.xpath('//image_url').first.text
      book = Book.new title: title, image_url: image_url, isbn: isbn

      [:ok, book]
    else
      [:error, response.code]
    end
  end
end
