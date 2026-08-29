# frozen_string_literal: true

require_relative 'bookmooch'
require_relative 'cache'
require_relative 'overdrive'

# WebSocket handlers for real-time updates
module Websockets
  module_function

  # Handle BookMooch import via WebSocket with progress updates
  def handle_bookmooch connection, session_id
    connection.write({type: 'connected', message: 'WebSocket connected'}.to_json)
    connection.flush

    book_info = Cache.get_by_id(session_id, :bookmooch_book_info)
    username = Cache.get_by_id(session_id, :bookmooch_username)
    password = Cache.get_by_id(session_id, :bookmooch_password)

    unless book_info && username && password
      connection.write({type: 'error', message: 'Missing job parameters'}.to_json)
      connection.flush
      connection.close
      return
    end

    run_import(connection, session_id, book_info, username, password)
  rescue Bookmooch::AuthenticationError, Bookmooch::RateLimitError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    write_error(connection, e.message)
    connection.close
  rescue StandardError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    write_error(connection, "An error occurred: #{e.message}")
    connection.close
  end

  # Handle the OverDrive availability check via WebSocket with progress updates.
  #
  # This exists because the work does not fit in a request. RequestTimeout caps
  # requests at 25s to stay under Render's proxy, and a large shelf takes longer
  # than that against OverDrive (#1347). The middleware skips WebSocket
  # upgrades, so running it here is what makes the slow path possible at all.
  def handle_availability connection, session_id
    connection.write({type: 'connected', message: 'WebSocket connected'}.to_json)
    connection.flush

    book_info = Cache.get_in_session(session_id, :availability_book_info)
    consortium = Cache.get_in_session(session_id, :availability_consortium)

    unless book_info && consortium
      write_error(connection, 'Missing job parameters')
      connection.close
      return
    end

    run_availability(connection, session_id, book_info, consortium)
  rescue StandardError => e
    # Everything in here is OverDrive work, so the message names OverDrive
    # rather than leaking an exception string. Overdrive::ApiError is not
    # caught separately: it belongs to the zip code library search, and nothing
    # on this path raises it.
    Sentry.capture_exception(e) if defined?(Sentry)
    write_error(connection, 'We could not reach OverDrive for that library. Please try another.')
    connection.close
  end

  def run_availability connection, session_id, book_info, consortium
    closed = false
    overdrive = Overdrive.new(book_info, consortium)
    titles = overdrive.fetch_titles_availability do |progress|
      next if closed

      connection.write(progress.to_json)
      connection.flush
    rescue IOError
      closed = true
    end

    # Cached whether or not the browser is still listening: they may have
    # navigated away, and the results page reads from here either way.
    Cache.set_in_session(
      session_id,
      titles:,
      collection_token: overdrive.collection_token,
      website_id: overdrive.website_id,
      library_url: overdrive.library_url
    )
    return if closed

    connection.write({type: 'complete', message: "Found #{titles.size} titles.", titles_count: titles.size}.to_json)
    connection.flush
    connection.close
  end

  def run_import connection, session_id, book_info, username, password
    closed = false
    books_added, books_failed = Bookmooch.books_added_and_failed(book_info, username, password) do |progress|
      next if closed

      connection.write(progress.to_json)
      connection.flush
    rescue IOError
      closed = true
    end

    Cache.set_by_id(session_id, books_added:, books_failed:)
    record_bookmooch_imports(session_id, books_added)
    return if closed

    connection.write(
      {
        type: 'complete',
        message: "Import complete! Added #{books_added.size} books.",
        books_added_count: books_added.size,
        books_failed_count: books_failed.size
      }.to_json
    )
    connection.flush
    connection.close
  end

  def record_bookmooch_imports session_id, books_added
    user_id = Cache.get_by_id(session_id, :bookmooch_user_id)
    return unless user_id

    shelf_name = Cache.get_by_id(session_id, :bookmooch_shelf_name)
    BookmoochImport.record_imports(user_id, books_added, shelf_name: shelf_name)
  end

  def write_error connection, message
    connection.write({type: 'error', message:}.to_json)
    connection.flush
  rescue StandardError
    nil
  end
end
