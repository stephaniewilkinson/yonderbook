# frozen_string_literal: true

require 'nokogiri'
require 'oauth'
require 'typhoeus'
require 'uri'
require 'pry'

module Goodreads
  Book = Struct.new :title, :image_url, :isbn, keyword_init: true

  BASE_URL = 'https://www.goodreads.com'
  API_KEY = ENV.fetch 'GOODREADS_API_KEY'
  SECRET  = ENV.fetch 'GOODREADS_SECRET'

  module_function

  def new_request_token
    consumer = OAuth::Consumer.new API_KEY, SECRET, site: BASE_URL
    consumer.get_request_token
  end

  def fetch_shelves goodreads_user_id
    params = URI.encode_www_form user_id: goodreads_user_id, key: API_KEY
    path = "/shelf/list.xml?#{params}}"

    doc = Nokogiri::XML Typhoeus.get("#{BASE_URL}/#{path}").body
    shelf_names = doc.xpath('//shelves//name').children.to_a
    shelf_books = doc.xpath('//shelves//book_count').children.to_a.map { |s| s.to_s.to_i }
    shelf_names.zip shelf_books
  end

  def get_books shelf_name, goodreads_user_id
    params = URI.encode_www_form shelf: shelf_name, per_page: '200', key: API_KEY
    path = "/review/list/#{goodreads_user_id}.xml?#{params}}"
    doc = Nokogiri::XML Typhoeus.get("#{BASE_URL}/#{path}").body
    number_of_pages = doc.xpath('//books').first['numpages'].to_i

    hydra = Typhoeus::Hydra.new
    requests = 1.upto(number_of_pages).map do |page|
      Typhoeus::Request.new "#{BASE_URL}/#{path}&page=#{page}"
    end
    requests.each { |request| hydra.queue request }

    hydra.run

    requests.flat_map do |request|
      doc = Nokogiri::XML request.response.body
      isbns = doc.xpath('//isbn').children.map(&:text)
      image_urls = doc.xpath('//book/image_url').children.map(&:text).grep_v(/\A\n\z/)
      titles = doc.xpath('//title').children.map(&:text)
      isbns.zip(image_urls, titles)
    end
  end

  def fetch_user access_token
    response = access_token.get "#{BASE_URL}/api/auth_user"
    xml = Nokogiri::XML response.body
    user_id = xml.xpath('//user').first.attributes.first[1].value
    first_name = xml.xpath('//user').first.children[1].children.text

    [user_id, first_name]
  end

  def fetch_book_data isbn
    response = Typhoeus.get "#{BASE_URL}/book/isbn/#{isbn}", params: {key: API_KEY}
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
