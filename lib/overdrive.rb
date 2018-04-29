# frozen_string_literal: true

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
    books = isbnset.map do |book|
      availability_url = "#{Overdrive::API_URI}/collections/#{collection_token}/products?q=#{URI.encode("\"#{book[2]}\"")}"
      response = HTTP.auth("Bearer #{token}").get(availability_url)
      products = JSON.parse(response.body)['products']

      Title.new isbn: book[0],
                image: book[1],
                title: book[2],
                id: products&.dig(0, 'crossRefId'),
                availability_url: products&.dig(0, 'links')&.assoc('availability')&.dig(-1, 'href'),
                url: products&.dig(0, 'contentDetails', 0, 'href')
    end

    books.map do |book|
      next book unless book.id

      response = HTTP.auth("Bearer #{token}").get(book.availability_url)
      book_body = JSON.parse(response.body)
      book.copies_available = book_body['copiesAvailable'] || 0
      book.copies_owned = book_body['copiesOwned'] || 0
      book
    end
  end
end
