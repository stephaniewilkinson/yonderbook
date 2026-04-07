# frozen_string_literal: true

# Route helper methods: import tracking, caching, Goodreads/BookMooch integration, Sentry
module RouteHelpers
  def fetch_and_cache_request_token
    Auth.fetch_request_token.tap { |token| Cache.set(session, request_token: token) if token }
  rescue StandardError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  def require_goodreads request
    unless @user&.goodreads_connected?
      flash[:error] = 'Please connect your Goodreads account first'
      request.redirect '/connections/goodreads'
    end
    load_goodreads_connection
  end

  def load_goodreads_connection
    @goodreads_connection = @user.goodreads_connection
    @goodreads_user_id = @goodreads_connection.goodreads_user_id
  end

  def cached_or_fetch key
    Cache.get(session, key) || yield.tap { |value| Cache.set(session, key => value) }
  end

  def sort_by_date_added books
    books.sort_by { |book| book.date_added || '' }.reverse
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

  def start_goodreads_import shelf_name
    return unless Fiber.scheduler

    sid = session['session_id']
    access_token = @goodreads_connection.oauth_access_token
    goodreads_user_id = @goodreads_user_id
    Async::Task.current.async(transient: true) do |task|
      task.with_timeout(20) do
        Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: 'goodreads', message: "Background fetch '#{shelf_name}'"))
        book_info = Goodreads.get_books(shelf_name, goodreads_user_id, access_token)
        Cache.set_by_id(sid, goodreads_shelf_data: book_info, goodreads_shelf_ready: true)
      end
    rescue StandardError => e
      Sentry.capture_exception(e) if defined?(Sentry)
      Cache.set_by_id(sid, goodreads_shelf_ready: true, goodreads_shelf_error: e.message)
    end
    true
  end

  def load_or_start_shelf_import shelf_name
    already_running = session['pending_import_type'] == 'goodreads'
    return if already_running || start_shelf_import(shelf_name)

    # Async not available, fall back to blocking fetch
    fetch_shelf_blocking(shelf_name)
  end

  def fetch_shelf_blocking shelf_name
    Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: 'goodreads', message: "Blocking fetch '#{shelf_name}'"))
    access_token = @goodreads_connection.oauth_access_token
    Goodreads.get_books(shelf_name, @goodreads_user_id, access_token).tap do |data|
      Cache.set(session, shelf_name.to_sym => data)
    end
  end

  def start_shelf_import shelf_name
    return unless start_goodreads_import(shelf_name)

    set_pending_import('goodreads', "/connections/goodreads/shelves/#{shelf_name}")
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

  def load_background_shelf_data
    sid = session['session_id']
    data = Cache.get_by_id(sid, :goodreads_shelf_data)
    return unless data

    Cache.set(session, @shelf_name.to_sym => data)
    Cache.clear_by_id(sid)
    clear_pending_import
    data
  end

  def enrich_sentry request
    Sentry.set_user(id: @user.id, email: @user.email) if @user
    Sentry.set_tags(route: request.path)
  end

  def enrich_sentry_error request
    Sentry.set_context('request', {method: request.request_method, path: request.path, params: request.params.keys})
    Sentry.set_context('goodreads', {user_id: @goodreads_user_id, shelf: @shelf_name}) if @goodreads_user_id
  end
end
