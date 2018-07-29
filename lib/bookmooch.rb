# frozen_string_literal: true

require 'typhoeus'

module Bookmooch
  BASE_URL = 'http://api.bookmooch.com'

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password
    hydra = Typhoeus::Hydra.new
    requests_titles_and_images = isbns_and_image_urls.map do |isbn, image_url, title|
      params = {asins: isbn, target: 'wishlist', action: 'add'}
      request = Typhoeus::Request.new "#{BASE_URL}/api/userbook", params: params, username: username, password: password
      hydra.queue request
      [request, title, image_url]
    end
    hydra.run

    added_or_failed = requests_titles_and_images.partition do |request, _, _|
      request.response.body.to_s.strip == request.options[:params][:asins]
    end

    added_or_failed.map { |partition| partition.map { |_, title, image_url| [title, image_url] } }
  end
end
