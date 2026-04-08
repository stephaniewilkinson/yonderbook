# frozen_string_literal: true

system 'roda-parse_routes', '-f', 'routes.json', __FILE__ if ENV.fetch('RACK_ENV', 'development') == 'development'

require 'area'
require 'async'
require 'rack/host_redirect'
require 'roda'
require 'securerandom'
require 'sentry-ruby'
require 'tilt'
# require 'zbar'

require_relative 'lib/analytics'

# Ruby 4.0 removed CGI.parse; the oauth gem still uses it
require 'cgi'
unless CGI.respond_to?(:parse)
  def CGI.parse query_string
    URI.decode_www_form(query_string).each_with_object({}) do |(k, v), hash|
      (hash[k] ||= []) << v
    end
  end
end

require_relative 'lib/auth'
require_relative 'lib/bookmooch'
require_relative 'lib/cache'
require_relative 'lib/database'
require_relative 'lib/email'
require_relative 'lib/email_templates'
require_relative 'lib/goodreads'
require_relative 'lib/models'
require_relative 'lib/overdrive'
require_relative 'lib/route_helpers'
require_relative 'lib/websockets'

SESSION_SECRET = ENV.fetch('SESSION_SECRET').then do |s|
  raise 'SESSION_SECRET must be at least 64 bytes for security' if s.bytesize < 64 && ENV.fetch('RACK_ENV', 'development') == 'production'

  warn 'WARNING: SESSION_SECRET should be at least 64 bytes for security' if s.bytesize < 64
  s
end

require_relative 'lib/rodauth_config'

class App < Roda
  use Sentry::Rack::CaptureExceptions
  use Rack::HostRedirect, 'www.yonderbook.com' => 'yonderbook.com'

  plugin :head
  plugin :assets, css: 'styles.css', precompiled: 'assets/compiled_assets.json'
  plugin :assets_preloading
  plugin :public, root: 'assets', headers: {'Cache-Control' => 'public, max-age=604800'}
  plugin :flash
  plugin :sessions, secret: SESSION_SECRET
  plugin :route_csrf
  plugin :slash_path_empty
  plugin :render
  plugin :partials
  plugin :content_for
  plugin :typecast_params
  plugin :caching
  plugin :default_headers, 'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'
  plugin :websockets
  plugin :content_security_policy do |csp|
    csp.default_src :self
    csp.script_src :self, :unsafe_inline, 'https://cdn.jsdelivr.net', 'https://www.googletagmanager.com', 'https://www.google-analytics.com', 'https://embed.tawk.to'
    csp.style_src :self, :unsafe_inline, 'https://fonts.googleapis.com'
    csp.img_src :self, :data, 'https:'
    csp.font_src :self, 'https://fonts.gstatic.com'
    csp.connect_src :self, 'wss:', 'https://www.google-analytics.com', 'https://va.tawk.to', 'https://embed.tawk.to'
    csp.frame_src 'https://tawk.to'
    csp.frame_ancestors :none
    csp.form_action :self, 'https://www.goodreads.com'
  end

  plugin :rodauth, auth_class: RodauthConfig

  compile_assets
  include RouteHelpers

  # TODO: figure out how to reroute 404s to /
  route do |r|
    r.public
    r.assets
    r.get('health') { 'ok' } # route: GET /health
    rodauth.check_session_expiration
    rodauth.check_active_session
    begin
      r.rodauth
    rescue Roda::RodaPlugins::RouteCsrf::InvalidToken
      flash[:error] = 'Your session has expired. Please try again.'
      r.redirect r.path
    end
    @user = Account[rodauth.session_value] if rodauth.logged_in?
    enrich_sentry(r)
    session['session_id'] ||= SecureRandom.uuid
    # route: WebSocket /ws/bookmooch/:session_id
    r.on 'ws', 'bookmooch', String do |session_id|
      r.websocket { |connection| Websockets.handle_bookmooch(connection, session_id) }
    end
    r.get('import-status') { import_status.to_json } # route: GET /import-status
    r.get('check-email') do # route: GET /check-email
      @pending_email = session.delete('pending_email') || 'your email'
      view 'check-email'
    end

    r.root do # route: GET /
      request_token = fetch_and_cache_request_token
      @auth_url = request_token&.authorize_url
      Analytics.track session['session_id'], 'page_viewed', page: 'welcome'
      view 'welcome'
    end

    r.is 'login' do
      request_token = Cache.get session, :request_token
      unless request_token
        flash[:error] = "Click 'login' again please"
        r.redirect '/'
      end
      # route: GET /login
      r.get do
        unless @user
          flash[:error] = 'Please log in first before connecting Goodreads'
          r.redirect '/'
        end
        Goodreads.fetch_user request_token, @user.id
        @user.refresh
        gr_user_id = @user.goodreads_connection&.goodreads_user_id
        Analytics.identify session['session_id'], goodreads_user_id: gr_user_id
        Analytics.track session['session_id'], 'goodreads_connected', goodreads_user_id: gr_user_id
        r.redirect '/goodreads/shelves'
      rescue OAuth::Unauthorized
        flash[:error] = 'Fetched details! Click login'
        r.redirect '/'
      end
    end

    r.get('about') { view 'about' } # route: GET /about
    r.get('faq') { view 'faq' } # route: GET /faq
    r.get('how-it-works') { view 'how_it_works' } # route: GET /how-it-works

    r.on 'account' do
      # route: POST /account/disconnect-goodreads
      r.post 'disconnect-goodreads' do
        rodauth.require_login
        check_csrf!
        GoodreadsConnection.where(user_id: @user.id).delete
        flash['notice'] = 'Your Goodreads connection has been removed and your data deleted.'
        r.redirect '/account'
      end

      # route: GET /account
      r.get do
        rodauth.require_login
        view 'account'
      end
    end

    r.get 'home' do # route: GET /home
      rodauth.require_login
      unless @user&.goodreads_connected?
        request_token = fetch_and_cache_request_token
        @auth_url = request_token&.authorize_url
      end
      view 'home'
    end

    r.on 'connections' do
      # route: GET /connections
      r.get true do
        @goodreads_connection = @user&.goodreads_connection
        view 'connections'
      end
    end

    r.on 'goodreads' do
      # route: GET /goodreads
      r.get true do
        r.redirect '/home' if @user&.goodreads_connected?
        request_token = fetch_and_cache_request_token
        @auth_url = request_token&.authorize_url
        view 'connect_goodreads'
      end

      r.on 'shelves' do
        require_goodreads r

        # route: GET /goodreads/shelves
        r.get true do
          @shelves = Goodreads.fetch_shelves @goodreads_user_id
          view 'shelves/index'
        end

        r.on String do |shelf_name|
          @shelf_name = shelf_name
          Cache.set session, shelf_name: @shelf_name
          @book_info = Cache.get(session, @shelf_name.to_sym) || load_background_shelf_data

          # route: GET /goodreads/shelves/:id
          r.get true do
            @book_info ||= load_or_start_shelf_import(@shelf_name)
            view('shelves/loading') unless @book_info
            @women, @men, @andy = Goodreads.get_gender @book_info
            @histogram_dataset = Goodreads.plot_books_over_time @book_info
            @ratings = Goodreads.rating_stats @book_info
            view 'shelves/show'
          end

          # Blocking fetch for sub-routes that need @book_info
          @book_info ||= fetch_shelf_blocking(@shelf_name)

          r.on 'bookmooch' do
            unless Bookmooch.available?
              flash[:error] = 'BookMooch appears to be down right now. Please try again later.'
              r.redirect "/goodreads/shelves/#{@shelf_name}"
            end

            # route: GET /goodreads/shelves/:id/bookmooch
            r.get true do
              @new_count, @skip_count, @no_isbn_count = bookmooch_preview(@user.id, @book_info)
              view 'shelves/bookmooch'
            end

            # route: POST /goodreads/shelves/:id/bookmooch?username=foo&password=baz
            r.post do
              BookmoochImport.clear_imports(@user.id) if r.params['reimport'] == '1'
              filtered = filter_already_imported_books(@user.id, @book_info)
              cache_bookmooch_params(r, filtered, @user.id, @book_info.size - filtered.size)
              set_pending_import('bookmooch', "#{r.path}/results", progress_url: "#{r.path}/progress")
              r.redirect 'bookmooch/progress'
            end

            # route: GET /goodreads/shelves/:id/bookmooch/progress
            r.get 'progress' do
              @session_id = session['session_id']
              view 'bookmooch_progress'
            end

            r.get 'results' do # route: GET /goodreads/shelves/:id/bookmooch/results
              @books_added, @books_failed, @books_failed_no_isbn, @skipped_count = load_bookmooch_results
              view 'bookmooch'
            end
          end

          r.is 'overdrive' do
            r.get(true) { view 'shelves/overdrive' } # route: GET /goodreads/shelves/:id/overdrive
            r.post do # route: POST /goodreads/shelves/:id/overdrive?consortium=1047
              consortium = typecast_params.pos_int('consortium')
              unless consortium
                flash[:error] = 'Invalid library selection'
                r.redirect "/goodreads/shelves/#{@shelf_name}/overdrive"
              end
              overdrive = Overdrive.new(@book_info, consortium)
              titles = overdrive.fetch_titles_availability
              Cache.set(session, titles:, collection_token: overdrive.collection_token, website_id: overdrive.website_id, library_url: overdrive.library_url)
              r.redirect '/goodreads/availability'
            end
          end
        end
      end

      r.is 'availability' do
        require_goodreads r
        r.get do # route: GET /goodreads/availability
          @titles = Cache.get session, :titles
          @collection_token = Cache.get session, :collection_token
          @website_id = Cache.get session, :website_id
          @library_url = Cache.get session, :library_url
          unless @titles
            flash[:error] = 'Please choose a shelf first'
            r.redirect 'shelves'
          end
          @available_books = sort_by_date_added(@titles.select { |a| a.copies_available.positive? })
          @waitlist_books = sort_by_date_added(@titles.select { |a| a.copies_available.zero? && a.copies_owned.positive? })
          @no_isbn_books = sort_by_date_added(@titles.select(&:no_isbn))
          @unavailable_books = sort_by_date_added(@titles.select { |a| a.copies_owned.zero? && !a.no_isbn })
          view 'availability'
        end
      end
    end

    r.on 'libraries' do
      require_goodreads r

      r.post true do # route: POST /libraries?zipcode=90029
        @shelf_name = Cache.get session, :shelf_name
        zip = r.params['zipcode'].to_s

        if zip.empty?
          flash[:error] = 'You need to enter a zip code'
          r.redirect '/libraries'
        end
        unless zip.to_latlon
          flash[:error] = 'please try a different zip code'
          r.redirect '/libraries'
        end
        @local_libraries = Overdrive.local_libraries zip.delete ' '
        Cache.set session, libraries: @local_libraries
        r.redirect '/libraries'
      end

      # route: GET /libraries
      r.get true do
        @shelf_name = Cache.get session, :shelf_name
        @local_libraries = Cache.get session, :libraries
        unless @local_libraries
          flash[:error] = 'Please choose a shelf first'
          r.redirect '/goodreads/shelves'
        end
        view 'library'
      end
    end
  rescue OAuth::Unauthorized, StandardError => e
    Analytics.track session['session_id'], 'error_occurred', error: e.class.name, message: e.message, path: r.path
    enrich_sentry_error(r)
    Sentry.capture_exception(e)

    # In production, redirect gracefully; in dev/test, raise to see full error
    raise e unless ENV['RACK_ENV'] == 'production'

    flash[:error] = 'That request took too long. Please try again.' if e.is_a?(RequestTimeout::Error)
    r.redirect '/'
  end
end
