# frozen_string_literal: true

require_relative 'bookmooch'
require_relative 'cache'

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
  rescue Bookmooch::AuthenticationError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    write_error(connection, e.message)
    connection.close
  rescue StandardError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    write_error(connection, "An error occurred: #{e.message}")
    connection.close
  end

  def run_import connection, session_id, book_info, username, password
    books_added, books_failed = Bookmooch.books_added_and_failed(book_info, username, password) do |progress|
      connection.write(progress.to_json)
      connection.flush
    end

    Cache.set_by_id(session_id, books_added:, books_failed:)

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

  def write_error connection, message
    connection.write({type: 'error', message:}.to_json)
    connection.flush
  rescue StandardError
    nil
  end
end
