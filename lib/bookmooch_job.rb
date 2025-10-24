# frozen_string_literal: true

require 'async'
require 'json'
require_relative 'bookmooch'
require_relative 'cache'

# Background job processor for BookMooch imports with progress tracking
module BookmoochJob
  module_function

  # Start a BookMooch import job in the background
  # Stores progress in cache and yields status updates via callback
  def run(book_info, username, password, session_id, &)
    Async do
      yield(type: 'status', message: 'Starting BookMooch import...')

      # Call the BookMooch import with progress tracking
      books_added, books_failed = Bookmooch.books_added_and_failed(book_info, username, password, &)

      # Store results in cache
      Cache.set_by_id session_id, books_added: books_added, books_failed: books_failed

      yield(type: 'complete',
            message: "Import complete! Added #{books_added.size} books.",
            books_added_count: books_added.size,
            books_failed_count: books_failed.size)
    rescue Bookmooch::AuthenticationError => e
      yield(type: 'error', message: e.message)
    rescue StandardError => e
      yield(type: 'error', message: "An error occurred: #{e.message}")
    end
  end
end
