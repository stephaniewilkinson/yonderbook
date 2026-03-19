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
require_relative 'lib/goodreads'
require_relative 'lib/models'
require_relative 'lib/overdrive'
require_relative 'lib/rodauth_config'
require_relative 'lib/route_helpers'
require_relative 'lib/websockets'

SESSION_SECRET = ENV.fetch('SESSION_SECRET').then do |s|
  warn 'WARNING: SESSION_SECRET should be at least 64 bytes for security' if s.bytesize < 64
  s
end

class App < Roda
  use Sentry::Rack::CaptureExceptions
  use Rack::HostRedirect, 'www.yonderbook.com' => 'yonderbook.com'

  plugin :head
  plugin :assets, css: 'styles.css'
  plugin :assets_preloading
  plugin :public, root: 'assets'
  plugin :flash
  plugin :sessions, secret: SESSION_SECRET
  plugin :route_csrf
  plugin :slash_path_empty
  plugin :render
  plugin :partials
  plugin :content_for
  plugin :default_headers, 'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'
  plugin :websockets
  plugin :hash_branches

  plugin :rodauth, &RODAUTH_CONFIG

  compile_assets
  include RouteHelpers

  require_relative 'routes/connections'

  # TODO: figure out how to reroute 404s to /
  route do |r|
    r.public
    r.assets
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
        r.redirect '/connections/goodreads/shelves'
      rescue OAuth::Unauthorized
        flash[:error] = 'Fetched details! Click login'
        r.redirect '/'
      end
    end

    # route: GET /about
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

    r.is 'home' do
      # route: GET /home
      r.get do
        rodauth.require_login
        unless @user&.goodreads_connected?
          request_token = fetch_and_cache_request_token
          @auth_url = request_token&.authorize_url
        end
        view 'home'
      end
    end

    r.hash_branches
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
