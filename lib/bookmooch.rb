# frozen_string_literal: true

require 'typhoeus'

module Bookmooch
  BASE_URL = 'http://api.bookmooch.com'

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password
    books_added = []
    books_failed = []

    isbns_and_image_urls.each do |isbn, image_url, title|
      params = {asins: isbn, target: 'wishlist', action: 'add'}

      response = Typhoeus.get "#{BASE_URL}/api/userbook", params: params, username: username, password: password

      if response.body.to_s.strip == isbn
        books_added << [title, image_url]
      else
        books_failed << [title, image_url]
      end
    end

    [books_added, books_failed]
  end
end
