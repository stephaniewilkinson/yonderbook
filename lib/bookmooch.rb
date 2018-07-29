# frozen_string_literal: true

require 'typhoeus'

module Bookmooch
  BASE_URL = 'http://api.bookmooch.com'

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password
    hydra = Typhoeus::Hydra.new
    requests_images_and_titles = isbns_and_image_urls.map do |isbn, image_url, title|
      params = {asins: isbn, target: 'wishlist', action: 'add'}
      request = Typhoeus::Request.new "#{BASE_URL}/api/userbook", params: params, username: username, password: password
      hydra.queue request
      [request, image_url, title]
    end
    hydra.run

    added_or_failed = requests_images_and_titles.partition do |request, image_url, title|
      request.response.body.to_s.strip == request.options[:params][:asins]
    end

    added_or_failed.map { |partition| partition.map { |_, image_url, title| [image_url, title] } }
  end
end
