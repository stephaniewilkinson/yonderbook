# frozen_string_literal: true

require 'async'
require 'async/http/internet/instance'
require 'json'

module AlternateIsbns
  BASE_URL = 'https://openlibrary.org'
  # Open Library API rate limit is 180 req/min = 3 req/sec
  # Each ISBN makes 2 API calls: Books API lookup, work editions
  # Process 1 ISBN per second = 2 API calls/sec (safely under 3 req/sec limit)
  DELAY_BETWEEN_REQUESTS = 1.0
  MAX_RETRIES = 3

  module_function

  # Takes an array of ISBNs, returns a hash mapping each ISBN to its alternate editions
  # Example: { '9780140328721' => ['9780141311234', '9780142410387'], ... }
  def fetch_alternate_isbns isbns
    Console.logger.info "AlternateIsbns: Processing #{isbns.count} ISBNs sequentially (1 per second)"
    Console.logger.info "AlternateIsbns: Estimated time: ~#{isbns.count} seconds"

    result = {}

    isbns.each_with_index do |isbn, index|
      alternates = fetch_alternates_for_isbn_with_retry(isbn)
      unless alternates.empty?
        result[isbn] = alternates
        Console.logger.info "AlternateIsbns: [#{index + 1}/#{isbns.count}] Found #{alternates.count} alternates for #{isbn}"
      end

      # Rate limit: wait 1 second before next request (except for last one)
      sleep DELAY_BETWEEN_REQUESTS unless index == isbns.count - 1
    rescue StandardError => e
      Console.logger.error "AlternateIsbns: Error processing ISBN #{isbn}: #{e.message}"
    end

    Console.logger.info "AlternateIsbns: Successfully found alternates for #{result.count}/#{isbns.count} ISBNs"
    result
  end

  def fetch_alternates_for_isbn_with_retry isbn, attempt = 1
    fetch_alternates_for_isbn(isbn)
  rescue StandardError => e
    if attempt < MAX_RETRIES
      delay = 2**attempt # Exponential backoff: 2s, 4s, 8s
      Console.logger.warn "AlternateIsbns: Retry #{attempt}/#{MAX_RETRIES} for ISBN #{isbn} after #{delay}s"
      sleep delay
      fetch_alternates_for_isbn_with_retry(isbn, attempt + 1)
    else
      Console.logger.error "AlternateIsbns: Failed after #{MAX_RETRIES} retries for ISBN #{isbn}: #{e.message}"
      []
    end
  end

  def fetch_alternates_for_isbn isbn
    edition = fetch_edition_by_isbn(isbn)
    return [] unless edition

    work_key = extract_work_key(edition)
    return [] unless work_key

    editions = fetch_work_editions(work_key)
    extract_isbns_from_editions(editions)
  end

  def fetch_edition_by_isbn isbn
    # Use Books API to avoid redirects
    url = "#{BASE_URL}/api/books?bibkeys=ISBN:#{isbn}&format=json&jscmd=details"
    response = Async::HTTP::Internet.get(url)

    case response.status
    when 200
      data = JSON.parse(response.read)
      book_data = data["ISBN:#{isbn}"]

      if book_data && book_data['details']
        Console.logger.debug "AlternateIsbns: Fetched edition for ISBN #{isbn}"
        book_data['details']
      else
        Console.logger.debug "AlternateIsbns: ISBN #{isbn} not found in Books API"
        nil
      end
    when 429
      # Rate limited - raise error to trigger retry
      raise 'Rate limited (429)'
    else
      Console.logger.warn "AlternateIsbns: ISBN #{isbn} returned unexpected status #{response.status}"
      nil
    end
  rescue JSON::ParserError => e
    Console.logger.error "AlternateIsbns: JSON parse error for ISBN #{isbn}: #{e.message}"
    nil
  ensure
    response&.close
  end

  def extract_work_key edition
    works = edition['works']
    return unless works && !works.empty?

    # Extract work key from the first work (e.g., "/works/OL45804W" -> "OL45804W")
    works.first['key']&.split('/')&.last
  end

  def fetch_work_editions work_key
    response = Async::HTTP::Internet.get("#{BASE_URL}/works/#{work_key}/editions.json")

    case response.status
    when 200
      data = JSON.parse(response.read)
      data['entries'] || []
    when 429
      # Rate limited - raise error to trigger retry
      raise 'Rate limited (429)'
    else
      []
    end
  rescue JSON::ParserError
    []
  ensure
    response&.close
  end

  def extract_isbns_from_editions editions
    isbns = []

    editions.each do |edition|
      # ISBN 13s
      isbn_13s = edition['isbn_13'] || []
      isbns.concat(isbn_13s)

      # ISBN 10s
      isbn_10s = edition['isbn_10'] || []
      isbns.concat(isbn_10s)
    end

    isbns.compact.uniq
  end
end
