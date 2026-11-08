# frozen_string_literal: true

# Getting a Goodreads shelf into the cache without fetching it inside the
# request: a large shelf takes longer than RequestTimeout allows. Starts the
# fetch in the background and shows the loading page, which reloads once it is
# in. Relies on RouteHelpers for set_pending_import and clear_pending_import.
module ShelfLoading
  # Not tied to any request: the loading page polls until this finishes. It was
  # 20s, under RequestTimeout's 25s, so the shelves too big for a request were
  # too big for this as well. Still bounded, so a hung Goodreads connection ends
  # in the loading page's error message instead of a page that polls forever.
  BACKGROUND_FETCH_TIMEOUT = 90

  def start_goodreads_import shelf_name
    return unless Fiber.scheduler

    sid = session['session_id']
    access_token = @goodreads_connection.oauth_access_token
    goodreads_user_id = @goodreads_user_id
    Async::Task.current.async(transient: true) do |task|
      task.with_timeout(BACKGROUND_FETCH_TIMEOUT) do
        Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: 'goodreads', message: "Background fetch '#{shelf_name}'"))
        book_info = Goodreads.get_books(shelf_name, goodreads_user_id, access_token)
        Cache.set_by_id(sid, goodreads_shelf_data: book_info, goodreads_shelf_ready: true)
      end
    rescue StandardError => e
      Sentry.capture_exception(e)
      Cache.set_by_id(sid, goodreads_shelf_ready: true, goodreads_shelf_error: e.message)
    end
    true
  end

  # `return_to:` is where the import toast links once the shelf is in. The
  # loading page itself just reloads, so it lands back wherever it started.
  def load_or_start_shelf_import shelf_name, return_to: "/goodreads/shelves/#{shelf_name}"
    return if session['pending_import_type'] == 'goodreads'

    # This used to ask a helper whose return value was set_pending_import's --
    # nil, from its last assignment -- so a background start always looked like
    # a failure, and every caller fetched inline as well.
    if start_goodreads_import(shelf_name)
      set_pending_import('goodreads', return_to)
      return
    end

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

  def load_background_shelf_data
    sid = session['session_id']
    fail_background_shelf_import(sid) if Cache.get_by_id(sid, :goodreads_shelf_error)
    data = Cache.get_by_id(sid, :goodreads_shelf_data)
    return unless data

    Cache.set(session, @shelf_name.to_sym => data)
    Cache.clear_by_id(sid)
    clear_pending_import
    data
  end

  # A failed background fetch still marks itself ready, so the loading page
  # reloads -- and with no data and an import still pending, it used to render
  # the loading page again, poll, see ready, and reload, forever. The error was
  # written and never read.
  def fail_background_shelf_import sid
    Cache.clear_by_id(sid)
    clear_pending_import
    flash[:error] = 'We could not load that shelf from Goodreads. Please try again.'
    request.redirect '/goodreads/shelves'
  end

  # For a POST that needs the shelf after the cache expired. Sends them back to
  # the GET to load it rather than fetching it here, where it would time out.
  def redirect_to_reload_shelf request
    flash[:error] = 'Your shelf needed reloading. Please sign in to BookMooch again once it loads.'
    request.redirect request.path
  end
end
