# frozen_string_literal: true

module Overdrive
  API_URI    = 'https://api.overdrive.com/v1'
  MAPBOX_URI = 'https://www.overdrive.com/mapbox/find-libraries-by-location'
  OAUTH_URI  = 'https://oauth.overdrive.com'
  KEY        = ENV.fetch 'OVERDRIVE_KEY'
  SECRET     = ENV.fetch 'OVERDRIVE_SECRET'

  Title = Struct.new :title, :image, :copies_available, :copies_owned, :isbn, :url, keyword_init: true

  module_function

  def fetch_products_info book, collection_token, token
    availability_uri = "#{Overdrive::API_URI}/collections/#{collection_token}/products?q=#{URI.encode("\"#{book[2]}\"")}"
    response = HTTP.auth("Bearer #{token}").get(availability_uri)
    JSON.parse(response.body)['products']
  end

  def fetch_titles_availability isbnset, collection_token, token
    isbnset.map do |book|

      products = fetch_products_info book, collection_token, token

      if products
        availibility_url = products.first['links'].assoc('availability').last['href']
        response = HTTP.auth("Bearer #{token}").get(availibility_url)
        book_body = JSON.parse(response.body)
        copies_available = book_body['copiesAvailable']
        copies_owned = book_body['copiesOwned']
        url = products.first['contentDetails'].first['href']
      end

      Title.new isbn: book[0],
                image: book[1],
                title: book[2],
                copies_available: copies_available || 0,
                copies_owned: copies_owned || 0,
                url: url
    end
  end
end
