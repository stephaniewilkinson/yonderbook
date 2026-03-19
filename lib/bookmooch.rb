# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/client'
require 'async/http/endpoint'
require 'base64'
require 'uri'
require_relative 'alternate_isbns'

module Bookmooch
  BASE_URL = 'https://api.bookmooch.com'
  PATH = '/api/userbook'

  class AuthenticationError < StandardError; end

  module_function

  def books_added_and_failed isbns_and_image_urls, username, password, &progress_callback
    original_isbns = isbns_and_image_urls.map { |h| h[:isbn] }.reject(&:empty?)

    # Fetch and expand ISBNs with alternates
    progress_callback&.call(type: 'status', message: "Fetching alternate ISBNs for #{original_isbns.size} books...")
    alternate_isbn_map = AlternateIsbns.fetch_alternate_isbns(original_isbns, &progress_callback)
    expanded_isbns, isbn_to_original = expand_isbns_with_alternates(original_isbns, alternate_isbn_map)

    progress_callback&.call(type: 'status', message: "Sending #{expanded_isbns.size} ISBNs to BookMooch...")

    # Send all ISBNs to BookMooch
    added_isbns = send_expanded_isbns(expanded_isbns, username, password, &progress_callback)

    progress_callback&.call(type: 'status', message: 'Processing results...')

    # Map successfully added ISBNs back to original ISBNs and track best ISBN for each book
    successfully_added_originals, original_to_best_isbn = map_to_originals_with_best_isbn(added_isbns, isbn_to_original)

    # Add BookMooch ISBN to each book for linking
    isbns_and_image_urls.each do |book|
      book[:bookmooch_isbn] = original_to_best_isbn[book[:isbn]] if original_to_best_isbn[book[:isbn]]
    end

    isbns_and_image_urls.partition { |h| successfully_added_originals.include? h[:isbn] }
  end

  def send_expanded_isbns(expanded_isbns, username, password, &)
    # Batch size of 137 keeps URLs under 2000 chars (max URL length ~2048)
    # Each ISBN-13: 13 chars + '+' = 14 chars
    # 137 ISBNs * 14 = 1918 chars + 72 (base URL) = 1990 chars
    batch_size = 137
    isbn_batches = expanded_isbns.each_slice(batch_size).map { |isbn_batch| isbn_batch.join('+') }

    send_isbn_batches(isbn_batches, username, password, &)
  end

  def map_to_originals_with_best_isbn added_isbns, isbn_to_original
    successfully_added_originals = []
    original_to_best_isbn = {}

    # For each added ISBN, map it back to its original and track the first ISBN found
    # (first = original ISBN if it was added, otherwise first alternate that worked)
    added_isbns.each do |isbn|
      original_isbn = isbn_to_original[isbn]
      next unless original_isbn

      unless successfully_added_originals.include?(original_isbn)
        successfully_added_originals << original_isbn
        original_to_best_isbn[original_isbn] = isbn
      end
    end

    [successfully_added_originals, original_to_best_isbn]
  end

  def expand_isbns_with_alternates original_isbns, alternate_isbn_map
    expanded_isbns = []
    isbn_to_original = {}

    original_isbns.each do |original_isbn|
      # Add the original ISBN
      expanded_isbns << original_isbn
      isbn_to_original[original_isbn] = original_isbn

      # Add all alternate ISBNs if available
      alternates = alternate_isbn_map[original_isbn]
      next unless alternates

      alternates.each do |alternate_isbn|
        expanded_isbns << alternate_isbn
        isbn_to_original[alternate_isbn] = original_isbn
      end
    end

    [expanded_isbns.uniq, isbn_to_original]
  end

  def send_isbn_batches isbn_batches, username, password, &progress_callback
    async_isbns = Async do
      endpoint = Async::HTTP::Endpoint.parse BASE_URL
      client = Async::HTTP::Client.new endpoint, limit: 64
      barrier = Async::Barrier.new
      headers = auth_headers(username, password)
      added_isbns = []
      total_batches = isbn_batches.size

      isbn_batches.each.with_index do |isbn_batch, batch_idx|
        barrier.async do
          process_batch(client, isbn_batch, batch_idx, headers, added_isbns)
          progress_callback&.call(
            type: 'progress',
            message: "Processing batch #{batch_idx + 1} of #{total_batches}...",
            current: batch_idx + 1,
            total: total_batches
          )
        end
      end

      begin
        barrier.wait
      ensure
        barrier&.stop
      end

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

  def process_batch client, isbn_batch, _batch_idx, headers, added_isbns
    params = URI.encode_www_form(asins: isbn_batch, target: 'wishlist', action: 'add')
    path = "#{PATH}?#{params}"

    response = client.get path, headers
    response_body = response.read

    collect_added_isbns(response_body, added_isbns)
  ensure
    response&.close
  end

  def collect_added_isbns response_body, added_isbns
    # Check if response is HTML error page
    if response_body&.match?(/\A\s*<(!DOCTYPE|html)/i)
      raise AuthenticationError, 'Invalid BookMooch credentials. Try using your username, not your email address.'
    end

    response_body&.lines(chomp: true)&.each do |isbn|
      added_isbns << isbn
    end
  end
end
