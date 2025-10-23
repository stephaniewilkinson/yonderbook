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

  def books_added_and_failed isbns_and_image_urls, username, password
    original_isbns = isbns_and_image_urls.map { |h| h[:isbn] }.reject(&:empty?)
    empty_isbn_count = isbns_and_image_urls.count { |h| h[:isbn].empty? }
    Console.logger.info "BookMooch: Total books: #{isbns_and_image_urls.count}, " \
                        "Books with ISBNs: #{original_isbns.count}, Books without ISBNs: #{empty_isbn_count}"
    Console.logger.info "BookMooch: Starting with #{original_isbns.count} original ISBNs"

    # Fetch and expand ISBNs with alternates
    expanded_isbns, isbn_to_original = fetch_and_expand_isbns(original_isbns)

    # Send all ISBNs to BookMooch
    added_isbns = send_expanded_isbns(expanded_isbns, username, password)

    # Map successfully added ISBNs back to original ISBNs
    successfully_added_originals = map_to_originals(added_isbns, isbn_to_original, original_isbns.count)

    isbns_and_image_urls.partition { |h| successfully_added_originals.include? h[:isbn] }
  end

  def fetch_and_expand_isbns original_isbns
    Console.logger.info 'BookMooch: Fetching alternate ISBNs from Open Library...'
    alternate_isbn_map = AlternateIsbns.fetch_alternate_isbns(original_isbns)
    Console.logger.info "BookMooch: Found alternate ISBNs for #{alternate_isbn_map.count} books"

    expanded_isbns, isbn_to_original = expand_isbns_with_alternates(original_isbns, alternate_isbn_map)
    Console.logger.info "BookMooch: Expanded to #{expanded_isbns.count} total ISBNs (including alternates)"

    [expanded_isbns, isbn_to_original]
  end

  def send_expanded_isbns expanded_isbns, username, password
    isbn_batches = expanded_isbns.each_slice(300).map { |isbn_batch| isbn_batch.join('+') }
    Console.logger.info "BookMooch: Split into #{isbn_batches.count} batches"

    send_isbn_batches(isbn_batches, username, password, expanded_isbns.count)
  end

  def map_to_originals added_isbns, isbn_to_original, original_count
    successfully_added_originals = added_isbns.filter_map { |isbn| isbn_to_original[isbn] }.uniq
    Console.logger.info "BookMooch: Successfully added #{successfully_added_originals.count}/#{original_count} books"
    successfully_added_originals
  end

  def expand_isbns_with_alternates original_isbns, alternate_isbn_map
    expanded_isbns = []
    isbn_to_original = {}
    total_alternates_added = 0

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
        total_alternates_added += 1
      end
    end

    avg = total_alternates_added.to_f / alternate_isbn_map.count
    Console.logger.info "BookMooch: Added #{total_alternates_added} alternate ISBNs (avg: #{avg.round(1)} per book with alternates)"
    [expanded_isbns.uniq, isbn_to_original]
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
    # Check if response is HTML error page
    if response_body&.match?(/\A\s*<(!DOCTYPE|html)/i)
      Console.logger.error "BookMooch Batch #{batch_idx + 1}: Authentication failed - received HTML error page"
      Console.logger.error "First 200 chars: #{response_body[0..200]}"
      raise AuthenticationError, 'Invalid BookMooch credentials. Try using your username, not your email address.'
    end

    batch_added = 0
    response_body&.lines(chomp: true)&.each do |isbn|
      added_isbns << isbn
      batch_added += 1
      Console.logger.info "BookMooch: Successfully added ISBN #{isbn}"
    end
    Console.logger.info "BookMooch Batch #{batch_idx + 1}: Added #{batch_added}/#{batch_isbn_count} ISBNs"
  end
end
