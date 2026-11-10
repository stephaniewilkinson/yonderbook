# frozen_string_literal: true

require_relative 'date_added'

# Route helper methods: import tracking, caching, Goodreads/BookMooch integration, Sentry
module RouteHelpers
  # JSON that is safe to print raw inside a <script> block. JSON.generate leaves
  # "<" alone, so a book title containing "</script>" would end the block and
  # let the rest of the title run as markup. These \uXXXX forms are still
  # valid JSON and decode to the same strings. #1415
  JSON_SCRIPT_ESCAPES = {'<' => '\u003c', '>' => '\u003e', '&' => '\u0026', "\u2028" => '\u2028', "\u2029" => '\u2029'}.freeze

  def json_for_script value
    JSON.generate(value).gsub(/[<>&\u2028\u2029]/, JSON_SCRIPT_ESCAPES)
  end

  def fetch_and_cache_request_token
    cached = Cache.get(session, :request_token)
    return cached if cached

    Auth.fetch_request_token.tap { |token| Cache.set(session, request_token: token) if token }
  rescue StandardError => e
    Sentry.capture_exception(e)
    nil
  end

  def require_goodreads request
    return if imported_library?
    return load_goodreads_connection if @user&.goodreads_connected?

    flash['error'] = 'Please connect your Goodreads account or import your library first'
    request.redirect '/goodreads'
  end

  def store_goodreads_in_session credentials
    Cache.set(session, anon_goodreads_user_id: credentials[:user_id], anon_goodreads_token: credentials[:token], anon_goodreads_secret: credentials[:secret])
  end

  def goodreads_session_present?
    @goodreads_user_id = Cache.get(session, :anon_goodreads_user_id)
    token = Cache.get(session, :anon_goodreads_token)
    secret = Cache.get(session, :anon_goodreads_secret)
    return false unless @goodreads_user_id && token && secret

    @anon_access_token = Auth.rebuild_access_token(token, secret)
    true
  end

  # A visitor's uploaded library, held in the session cache (#1414). Only call
  # this after the session id is assigned (app.rb), never from the root route.
  def anonymous_library
    return @anonymous_library if defined?(@anonymous_library)

    @anonymous_library = @user ? nil : Cache.get(session, :anonymous_library)
  end

  # Goodreads failing is expected now that its API is deprecated, not a 500.
  # It used to fall through to the catch-all, which sent the reader to the
  # homepage with no word of why. Say so, and point at the CSV import, which
  # doesn't need Goodreads at all.
  def goodreads_failed request, error
    enrich_sentry_error request
    SentryCapture.capture_once error
    flash['error'] = if error.message.include?('HTTP 401')
      "Goodreads didn't accept your connection. It may have expired: connect again, or upload a CSV export instead."
    else
      "Goodreads didn't answer. Try again in a minute, or upload a CSV export instead."
    end
    flash['fathom_event'] = 'goodreads_unreachable'
    request.redirect '/import'
  end

  # Where a reader's shelves are listed: their account, or the anonymous flow.
  def shelves_path = @user ? '/goodreads/shelves' : '/search/shelves'

  # The anonymous flow runs on either a Goodreads connection or an uploaded
  # CSV export held in the session (#1414).
  def require_goodreads_session request
    return if anonymous_library || goodreads_session_present?

    flash['error'] = 'Connect Goodreads or upload a CSV export to get started'
    request.redirect(@user ? '/home' : '/')
  end

  def load_goodreads_connection
    @goodreads_connection = @user.goodreads_connection
    @goodreads_user_id = @goodreads_connection.goodreads_user_id
  end

  def cached_or_fetch key
    Cache.get(session, key) || yield.tap { |value| Cache.set(session, key => value) }
  end

  # OverDrive blocks some networks outright, answering the library lookup with a
  # 403 rather than JSON. Send the user back to the zip code form with a message
  # they can act on, instead of letting it surface as a bare 500.
  def fetch_local_libraries request, zip, fallback: nil
    Overdrive.local_libraries Geolocation.normalize_zip(zip)
  rescue Overdrive::ApiError => e
    Sentry.capture_exception(e)
    flash['error'] = 'We could not reach OverDrive to look up libraries. Please try again in a little while.'
    # Early warning for the scraped library lookup. #1411
    flash['fathom_event'] = 'library_lookup_failed'
    request.redirect fallback || (@shelf_name ? "/goodreads/shelves/#{@shelf_name}/overdrive" : '/goodreads/shelves')
  end

  def sort_by_date_added books
    DateAdded.sort_desc books
  end

  def import_status
    response['Content-Type'] = 'application/json'
    sid = session['session_id']
    type = session['pending_import_type']
    ready = case type
    when 'bookmooch' then sid && Cache.get_by_id(sid, :books_added) ? true : false
    when 'goodreads' then sid && Cache.get_by_id(sid, :goodreads_shelf_ready) ? true : false
    else false
    end
    {ready:}
  end

  def load_bookmooch_results
    sid = session['session_id']
    books_added = Cache.get_by_id(sid, :books_added) || []
    books_failed = Cache.get_by_id(sid, :books_failed) || []
    skipped_count = Cache.get_by_id(sid, :bookmooch_skipped) || 0
    Cache.clear_by_id sid
    clear_pending_import
    no_isbn, failed = books_failed.partition { |book| book[:isbn].nil? || book[:isbn].empty? }
    [books_added, failed, no_isbn, skipped_count]
  end

  def bookmooch_preview user_id, book_info
    already_imported = BookmoochImport.already_imported_isbns(user_id)
    with_isbn = book_info.select { |b| b[:isbn] && !b[:isbn].empty? }
    new_books = with_isbn.reject { |b| already_imported.include?(b[:isbn]) }
    [new_books.size, with_isbn.size - new_books.size, book_info.size - with_isbn.size]
  end

  def filter_already_imported_books user_id, book_info
    already_imported = BookmoochImport.already_imported_isbns(user_id)
    book_info.reject { |b| already_imported.include?(b[:isbn]) }
  end

  def cache_bookmooch_params request, book_info, user_id, skipped_count
    Cache.set_by_id(
      session['session_id'],
      bookmooch_book_info: book_info,
      bookmooch_username: request.params['username'],
      bookmooch_password: request.params['password'],
      bookmooch_user_id: user_id,
      bookmooch_skipped: skipped_count,
      bookmooch_shelf_name: @shelf_name
    )
  end

  def set_pending_import type, url, progress_url: nil
    session['pending_import_type'] = type
    session['pending_import_url'] = url
    session['pending_import_progress_url'] = progress_url
  end

  def clear_pending_import
    session.delete('pending_import_type')
    session.delete('pending_import_url')
    session.delete('pending_import_progress_url')
  end

  def enrich_sentry request
    # id without email. id is enough to count affected users, group by person
    # and join back to the database; email would put every account-holder's
    # address on every error they hit, for the length of Sentry's retention.
    Sentry.set_user(id: @user.id) if @user
    Sentry.set_tags(route: request.path)
  end

  def enrich_sentry_error request
    Sentry.set_context('request', {method: request.request_method, path: request.path, params: request.params.keys})
    Sentry.set_context('goodreads', {user_id: @goodreads_user_id, shelf: @shelf_name}) if @goodreads_user_id
  end
end
