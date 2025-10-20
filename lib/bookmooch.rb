# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'base64'
require 'uri'

module Bookmooch
  BASE_URL = 'https://api.bookmooch.com'
  PATH = '/api/userbook'

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password
    isbns = isbns_and_image_urls.map { |h| h[:isbn] }.reject(&:empty?)
    Console.logger.info "BookMooch: Starting with #{isbns.count} ISBNs"
    isbn_batches = isbns.each_slice(300).map { |isbn_batch| isbn_batch.join('+') }
    Console.logger.info "BookMooch: Split into #{isbn_batches.count} batches"

    added_isbns = send_isbn_batches(isbn_batches, username, password, isbns.count)
    isbns_and_image_urls.partition { |h| added_isbns.include? h[:isbn] }
  end

  def send_isbn_batches isbn_batches, username, password, total_count
    async_isbns = Async do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new
      headers = auth_headers(username, password)
      added_isbns = []

      isbn_batches.each.with_index do |isbn_batch, batch_idx|
        barrier.async { process_batch(client, isbn_batch, batch_idx, headers, added_isbns) }
      end

      begin
        barrier.wait
      ensure
        barrier&.stop
      end

      Console.logger.info "BookMooch TOTAL: Successfully added #{added_isbns.count}/#{total_count} ISBNs"
      added_isbns
    ensure
      client&.close
    end

    async_isbns.wait
  end

  def auth_headers username, password
    basic_auth_credentials = Base64.strict_encode64 "#{username}:#{password}"
    {'Authorization' => "Basic #{basic_auth_credentials}"}
  end

  def process_batch client, isbn_batch, batch_idx, headers, added_isbns
    params = URI.encode_www_form(asins: isbn_batch, target: 'wishlist', action: 'add')
    path = "#{PATH}?#{params}"

    response = client.get path, headers
    response_body = response.read
    batch_isbns = isbn_batch.split('+')

    log_batch_info(batch_idx, batch_isbns.count, response_body)
    collect_added_isbns(response_body, added_isbns, batch_idx, batch_isbns.count)
  ensure
    response&.close
  end

  def log_batch_info batch_idx, isbn_count, response_body
    Console.logger.info "BookMooch Batch #{batch_idx + 1}: Sent #{isbn_count} ISBNs"
    Console.logger.info "BookMooch Batch #{batch_idx + 1}: Response size: #{response_body&.bytesize || 0} bytes"
    Console.logger.info "BookMooch Batch #{batch_idx + 1}: Response lines: #{response_body&.lines&.count || 0}"
  end

  def collect_added_isbns response_body, added_isbns, batch_idx, batch_isbn_count
    batch_added = 0
    response_body&.lines(chomp: true)&.each do |isbn|
      added_isbns << isbn
      batch_added += 1
      Console.logger.info "BookMooch: Successfully added ISBN #{isbn}"
    end
    Console.logger.info "BookMooch Batch #{batch_idx + 1}: Added #{batch_added}/#{batch_isbn_count} ISBNs"
  end
end
