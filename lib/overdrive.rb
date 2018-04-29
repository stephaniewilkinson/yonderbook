# frozen_string_literal: true

require 'typhoeus'

module Overdrive
  API_URI    = 'https://api.overdrive.com/v1'
  MAPBOX_URI = 'https://www.overdrive.com/mapbox/find-libraries-by-location'
  OAUTH_URI  = 'https://oauth.overdrive.com'
  KEY        = ENV.fetch 'OVERDRIVE_KEY'
  SECRET     = ENV.fetch 'OVERDRIVE_SECRET'

  Title = Struct.new :title, \
                     :image, \
                     :copies_available, \
                     :copies_owned, \
                     :isbn, \
                     :url, \
                     :id, \
                     :availability_url, \
                     keyword_init: true

  module_function

  def fetch_titles_availability isbnset, collection_token, token
    hydra = Typhoeus::Hydra.new

    books =
      isbnset.map do |book|
        availability_url = "#{Overdrive::API_URI}/collections/#{collection_token}/products?minimum=false&q=#{URI.encode("\"#{book[2]}\"")}"

        request = Typhoeus::Request.new availability_url, headers: {'Authorization' => "Bearer #{token}"}
        hydra.queue request

        title = Title.new isbn: book[0],
                          image: book[1],
                          title: book[2],
                          copies_available: 0,
                          copies_owned: 0

        [title, request]
      end

    puts "Running hydra for books: #{books.size} ..."
    hydra.run
    puts 'Hydra complete ...'

    books.each do |book, request|
      body = request.response.body
      next if body.empty?
      json = JSON.parse body
      products = json['products']
      next unless products

      book.id = products.dig 0, 'id'
      book.url = products.dig 0, 'contentDetails', 0, 'href'
    end

    batches = books.map(&:first).select(&:id).map(&:id).each_slice(25)

    puts "Batches of 25: #{batches.size} ..."
    results =
      batches.flat_map do |batch|
        uri = "https://api.overdrive.com/v2/collections/#{collection_token}/availability?products=#{batch.join ','}"
        response = HTTP.auth("Bearer #{token}").get uri
        body = JSON.parse response.body

        body['availability']
      end

    results.each do |result|
      book = books.find { |book, _| book.id == result['reserveId'] }.first
      book.copies_available = result['copiesAvailable']
      book.copies_owned = result['copiesOwned']
      puts book
    end

    books.map(&:first)
  end
end
