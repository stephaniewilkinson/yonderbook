# frozen_string_literal: true

require 'nokogiri'
require 'dotenv'

module Goodreads
  Book = Struct.new :title, :image_url, :isbn, keyword_init: true

  URI = 'https://www.goodreads.com'
  API_KEY = ENV.fetch 'GOODREADS_API_KEY'
  SECRET  = ENV.fetch 'GOODREADS_SECRET'

  module_function

  def get_books path
    HTTP.persistent URI do |http|
      doc = Nokogiri::XML http.get(path).body

      number_of_pages = doc.xpath('//books').first['numpages'].to_i

      1.upto(number_of_pages).flat_map do |page|
        doc = Nokogiri::XML http.get("#{path}&page=#{page}").body
        isbns = doc.xpath('//isbn').children.map &:text
        image_urls = doc.xpath('//book/image_url').children.map(&:text).grep_v /\A\n\z/
        titles = doc.xpath('//title').children.map &:text
        isbns.zip(image_urls, titles)
      end
    end
  end

  def fetch_user access_token
    response = access_token.get "#{URI}/api/auth_user"
    xml = Nokogiri::XML response.body
    user_id = xml.xpath('//user').first.attributes.first[1].value
    first_name = xml.xpath('//user').first.children[1].children.text

    [user_id, first_name]
  end

  def fetch_book_data isbn
    response = HTTP.get "#{URI}/book/isbn/#{isbn}", params: {key: API_KEY}
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
