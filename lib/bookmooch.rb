# frozen_string_literal: true

require 'http'

module Bookmooch
  BASE_URL = 'http://api.bookmooch.com'

  module_function

  def books_added_and_failed auth, isbns_and_image_urls
    books_added = []
    books_failed = []

    HTTP.basic_auth(auth).persistent(BASE_URL) do |http|
      isbns_and_image_urls.each do |isbn, image_url, title|
        params = {asins: isbn, target: 'wishlist', action: 'add'}

        response = http.get '/api/userbook', params: params

        if response.body.to_s.strip == isbn
          books_added << [title, image_url]
        else
          books_failed << [title, image_url]
        end
      end
    end

    [books_added, books_failed]
  end