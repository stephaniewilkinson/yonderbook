# frozen_string_literal: true

require 'async'
require 'async/http/internet/instance'
require 'json'

module AlternateIsbns
  BASE_URL = 'https://openlibrary.org'

  module_function

  # Takes an array of ISBNs, returns a hash mapping each ISBN to its alternate editions
  # Example: { '9780140328721' => ['9780141311234', '9780142410387'], ... }
  def fetch_alternate_isbns isbns
    result = {}

    isbns.each do |isbn|
      alternates = fetch_alternates_for_isbn(isbn)
      result[isbn] = alternates unless alternates.empty?
    end

    result
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
    Sync do
      Async::HTTP::Internet.get("#{BASE_URL}/isbn/#{isbn}.json") do |response|
        return nil unless response.status == 200

        JSON.parse(response.read)
      end
    end
  rescue StandardError
    nil
  end

  def extract_work_key edition
    works = edition['works']
    return unless works && !works.empty?

    # Extract work key from the first work (e.g., "/works/OL45804W" -> "OL45804W")
    works.first['key']&.split('/')&.last
  end

  def fetch_work_editions work_key
    Sync do
      Async::HTTP::Internet.get("#{BASE_URL}/works/#{work_key}/editions.json") do |response|
        return [] unless response.status == 200

        data = JSON.parse(response.read)
        data['entries'] || []
      end
    end
  rescue StandardError
    []
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
