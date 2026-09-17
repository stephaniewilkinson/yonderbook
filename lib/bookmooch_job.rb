# frozen_string_literal: true

require 'async'
require 'json'
require 'sentry-ruby'
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
    # Both arms used to report to the user and to nobody else. The yield writes
    # a websocket frame, the Async block ends, and the exception is gone -- no
    # stderr line, no backtrace anywhere. Running inside Async makes that worse
    # rather than better: an exception in a task propagates nowhere useful, so
    # a rescue that reports nothing is genuinely the end of the line.
    #
    # Bad credentials and rate limits are expected failures and get a
    # breadcrumb, so they show up as context on whatever fails next. The
    # StandardError arm is the one that matters -- it catches the failures
    # nobody anticipated and it discarded the most information.
    #
    # username and password are in scope in this method and must stay out of
    # extra; lib/sentry_scrubber.rb would redact them, but not sending them is
    # the rule this file should follow. session_id stays out for the same
    # reason -- it is a bearer capability, not just a correlation id. It keys
    # the import's cached data (Cache.get_by_id) and it is already in the
    # websocket URL, so anyone holding it can read that import.
    rescue Bookmooch::AuthenticationError, Bookmooch::RateLimitError => e
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: 'bookmooch', message: e.class.name))
      yield(type: 'error', message: e.message)
    rescue StandardError => e
      Sentry.capture_exception(e, extra: {book_count: book_info.size})
      yield(type: 'error', message: "An error occurred: #{e.message}")
    end
  end
end
