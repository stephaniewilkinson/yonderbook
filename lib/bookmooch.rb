# frozen_string_literal: true

require 'typhoeus'

module Bookmooch
  BASE_URL = 'http://api.bookmooch.com'

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password
    hydra = Typhoeus::Hydra.new(max_concurrency: 200)
    isbn_batches = isbns_and_image_urls.map { |h| h[:isbn] }.reject(&:empty?).each_slice(300).map { |isbns| isbns.join('+') }

    requests = isbn_batches.map do |isbn_batch|
      params = {asins: isbn_batch, target: 'wishlist', action: 'add'}
      request = Typhoeus::Request.new "#{BASE_URL}/api/userbook", params: params, username: username, password: password
      hydra.queue request

      request
    end

    hydra.run

    added_isbns = requests.flat_map do |request|
      request.response.body.lines(chomp: true)
    end

    isbns_and_image_urls.partition { |h| added_isbns.include? h[:isbn] }
  end
end
