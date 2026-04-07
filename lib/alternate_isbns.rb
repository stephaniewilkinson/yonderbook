# frozen_string_literal: true

require 'async'
require 'async/barrier'
require 'async/http/internet/instance'
require 'async/limiter/generic'
require 'async/limiter/timing/leaky_bucket'
require 'async/semaphore'
require 'json'

module AlternateIsbns
  BASE_URL = 'https://openlibrary.org'
  # Open Library API rate limit is 180 req/min = 3 req/sec
  # Each ISBN makes 2 API calls: Books API lookup, work editions
  # Process 1.5 books per second = 3 API calls/sec (at rate limit)
  # Using 1.4 books/sec for safety margin
  BOOKS_PER_SECOND = 1.4
  MAX_RETRIES = 3

  module_function

  # Takes an array of ISBNs, returns a hash mapping each ISBN to its alternate editions
  # Example: { '9780140328721' => ['9780141311234', '9780142410387'], ... }
  def fetch_alternate_isbns isbns, &progress_callback
    result = {}
    total_isbns = isbns.size
    completed_count, uncached_isbns = load_cached_isbns(isbns, result)

    # Report cached progress in one update
    report_progress(progress_callback, completed_count, total_isbns) if completed_count.positive?

    # Fetch uncached ISBNs from Open Library API
    return result if uncached_isbns.empty?

    fetch_uncached_isbns(uncached_isbns, result, completed_count, total_isbns, &progress_callback)

    result
  end

  def load_cached_isbns isbns, result
    cached_results = IsbnAlternate.bulk_lookup(isbns)
    uncached = []
    count = 0

    isbns.each do |isbn|
      if cached_results.key?(isbn)
        result[isbn] = cached_results[isbn] unless cached_results[isbn].empty?
        count += 1
      else
        uncached << isbn
      end
    end

    [count, uncached]
  end

  def report_progress callback, current, total
    callback&.call(type: 'progress', message: "Fetching alternate ISBNs — #{current} of #{total} complete...", current: current, total: total)
  end

  def fetch_uncached_isbns uncached_isbns, result, completed_count, total_isbns, &progress_callback
    Sync do
      timing = Async::Limiter::Timing::LeakyBucket.new(BOOKS_PER_SECOND, BOOKS_PER_SECOND * 2)
      limiter = Async::Limiter::Generic.new(timing: timing)
      barrier = Async::Barrier.new
      semaphore = Async::Semaphore.new(4, parent: barrier)

      uncached_isbns.each do |isbn|
        semaphore.async do
          limiter.async do
            alternates, work_key = fetch_alternates_for_isbn_with_retry(isbn)
            result[isbn] = alternates unless alternates.empty?
            IsbnAlternate.store(isbn, alternates, work_key: work_key)
          rescue StandardError => e
            Sentry.capture_exception(e, extra: {isbn: isbn}) if defined?(Sentry)
          ensure
            completed_count += 1
            report_progress(progress_callback, completed_count, total_isbns)
          end
        end
      end

      barrier.wait
    ensure
      barrier&.stop
    end
  end

  def fetch_alternates_for_isbn_with_retry isbn, attempt = 1
    fetch_alternates_for_isbn(isbn)
  rescue StandardError
    if attempt < MAX_RETRIES
      delay = 2**attempt # Exponential backoff: 2s, 4s, 8s
      sleep delay
      fetch_alternates_for_isbn_with_retry(isbn, attempt + 1)
    else
      [[], nil]
    end
  end

  # Returns [alternates_array, work_key]
  def fetch_alternates_for_isbn isbn
    edition = fetch_edition_by_isbn(isbn)
    return [[], nil] unless edition

    # Extract ISBNs from the original edition (includes both ISBN-10 and ISBN-13)
    original_isbns = extract_isbns_from_edition(edition)

    work_key = extract_work_key(edition)
    return [original_isbns.reject { |i| i == isbn }, work_key] unless work_key

    editions = fetch_work_editions(work_key)
    alternate_isbns = extract_isbns_from_editions(editions)

    # Combine original ISBNs with alternates, remove the queried ISBN, and deduplicate
    [(original_isbns + alternate_isbns).uniq.reject { |i| i == isbn }, work_key]
  end

  def fetch_edition_by_isbn isbn
    # Use Books API to avoid redirects
    url = "#{BASE_URL}/api/books?bibkeys=ISBN:#{isbn}&format=json&jscmd=details"
    response = Async::HTTP::Internet.get(url)

    case response.status
    when 200
      data = JSON.parse(response.read)
      book_data = data["ISBN:#{isbn}"]
      book_data && book_data['details'] ? book_data['details'] : nil
    when 429
      # Rate limited - raise error to trigger retry
      raise 'Rate limited (429)'
    end
  rescue JSON::ParserError
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

  def isbn_13_to_isbn_10 isbn_13
    # ISBN-13 format: 978-XXXXXXXXX-C
    # ISBN-10 format: XXXXXXXXX-C (different check digit)
    # Only ISBN-13s starting with 978 can be converted to ISBN-10
    return unless isbn_13 && isbn_13.length == 13 && isbn_13.start_with?('978')

    # Extract the middle 9 digits (remove 978 prefix and check digit)
    base = isbn_13[3..11]

    # Calculate ISBN-10 check digit
    # Formula: (11 - ((10*d1 + 9*d2 + 8*d3 + ... + 2*d9) mod 11)) mod 11
    sum = 0
    base.chars.each_with_index do |digit, index|
      sum += digit.to_i * (10 - index)
    end

    check_digit = (11 - (sum % 11)) % 11
    check_char = check_digit == 10 ? 'X' : check_digit.to_s

    base + check_char
  end

  def extract_isbns_from_edition edition
    isbns = []

    # ISBN 13s
    isbn_13s = edition['isbn_13'] || []
    isbns.concat(isbn_13s)

    # Convert ISBN-13s to ISBN-10s where possible
    isbn_13s.each do |isbn_13|
      isbn_10 = isbn_13_to_isbn_10(isbn_13)
      isbns << isbn_10 if isbn_10
    end

    # ISBN 10s from OpenLibrary
    isbn_10s = edition['isbn_10'] || []
    isbns.concat(isbn_10s)

    isbns.compact.uniq
  end

  def extract_isbns_from_editions editions
    isbns = []

    editions.each do |edition|
      isbns.concat(extract_isbns_from_edition(edition))
    end

    isbns.compact.uniq
  end
end
