# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'base64'
require 'uri'

module Bookmooch
  BASE_URL = 'http://api.bookmooch.com'
  PATH = '/api/userbook'

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password
    isbns = isbns_and_image_urls.map { |h| h[:isbn] }.reject(&:empty?)
    isbn_batches = isbns.each_slice(300).map { |isbn_batch| isbn_batch.join('+') }

    async_isbns = Async do
      endpoint = Async::HTTP::Endpoint.parse(BASE_URL)
      client = Async::HTTP::Client.new(endpoint)
      barrier = Async::Barrier.new

      basic_auth_credentials = Base64.strict_encode64 "#{username}:#{password}"
      headers = {'Authorization' => "Basic #{basic_auth_credentials}"}

      added_isbns = []

      isbn_batches.each do |isbn_batch|
        params = URI.encode_www_form(asins: isbn_batch, target: 'wishlist', action: 'add')
        path = "#{PATH}?#{params}"

        barrier.async do
          response = client.get path, headers
          response.read.lines(chomp: true).each do |isbn|
            added_isbns << isbn
          end
        end
      end

      barrier.wait

      added_isbns
    ensure
      client&.close
    end

    isbns_and_image_urls.partition { |h| async_isbns.wait.include? h[:isbn] }
  end
end
