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

class App < Roda
  use Sentry::Rack::CaptureExceptions
  use Rack::HostRedirect, 'www.yonderbook.com' => 'yonderbook.com'

  plugin :head
  plugin :assets, css: 'styles.css'
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
  plugin :hash_branches
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

  # Rodauth configuration with email verification and password reset
  plugin :rodauth do
    db DB
    enable :login, :logout, :create_account, :verify_account, :reset_password, :lockout
    enable :email_auth, :argon2, :update_password_hash, :active_sessions
    enable :session_expiration, :disallow_common_passwords
    hmac_secret SESSION_SECRET
    allow_raw_email_token? true if ENV['RACK_ENV'] == 'test'

    # Base URL for email links
    base_url ENV.fetch('BASE_URL', 'http://localhost:9292')

    # Use password_hash column in accounts table instead of separate table
    password_hash_table :accounts
    password_hash_id_column :id
    password_hash_column :password_hash

    # Customize field labels and requirements
    login_label 'Email'
    login_param 'email'
    login_column :email
    login_input_type 'email'
    require_password_confirmation? false
    require_login_confirmation? false

    # Email verification configuration
    verify_account_set_password? false
    verify_account_autologin? true
    account_status_column :status_id
    account_open_status_value 2 # Verified status
    account_unverified_status_value 1 # Unverified status

    # Magic link (email auth) configuration
    use_multi_phase_login? false
    email_auth_email_subject 'Your Yonderbook Login Link'
    email_auth_email_sent_notice_flash 'Check your email for a login link!'
    email_auth_email_sent_redirect '/authenticate'
    email_auth_request_route 'email-auth-request'
    email_auth_route 'email-auth'

    # Allow direct magic link requests without multi-phase login session
    before_email_auth_request_route do
      login = param(login_param)
      account_from_login(login) if login && !login.empty? && !account
    end

    # Enable deadline values for password reset and email verification
    set_deadline_values? true

    # Change routes to avoid conflict with Goodreads OAuth callback
    login_route 'authenticate'
    create_account_route 'sign-up'
    verify_account_route 'verify-account'
    reset_password_request_route 'reset-password-request'
    reset_password_route 'reset-password'

    # Redirect to home page after successful auth actions
    login_redirect '/home'
    login_return_to_requested_location? true
    logout_redirect '/'
    verify_account_redirect '/home'

    # Session expiration: 30 min inactivity, 24 hour max lifetime
    session_inactivity_timeout 1800
    max_session_lifetime 86_400

    # Redirect to check-email interstitial after account creation
    create_account_redirect '/check-email'

    # Store email in session after account creation for the interstitial page
    after_create_account do
      session['pending_email'] = account[login_column]
    end

    # Email configuration
    email_from 'app@yonderbook.com'
    email_subject_prefix '[Yonderbook] '

    # Send emails using Resend with category tags
    send_email do |email|
      tag = case email.subject
      when /Verify/ then 'verify_account'
      when /Reset/ then 'reset_password'
      when /Login Link/ then 'email_auth'
      when /Unlock/ then 'unlock_account'
      else 'other'
      end
      EmailService.send_email(
        to: email.to.first,
        subject: email.subject,
        html: email.html_part&.body&.to_s || email.body.to_s,
        tags: [{name: 'category', value: tag}]
      )
    end

    # Custom error messages for better UX
    no_matching_login_message 'No account exists with that email. Please create an account.'
    reset_password_request_error_flash 'There was an error requesting a password reset. Please make sure the email is correct and that you have an account.'

    # Success notifications
    create_account_notice_flash 'Account created! Check your email to verify your account before logging in.'
    reset_password_email_sent_notice_flash 'We sent you a password reset link to your email. Click the link in the email to finish resetting your password.'
    reset_password_email_sent_redirect '/authenticate'

    # Rate limiting - lock account after 10 failed login attempts
    max_invalid_logins 10
    unlock_account_email_subject 'Unlock Your Yonderbook Account'

    # Email subjects and branded HTML bodies
    verify_account_email_subject 'Verify Your Yonderbook Account'
    verify_account_email_body { EmailTemplates.verify_account_body(verify_account_email_link) }
    reset_password_email_subject 'Reset Your Yonderbook Password'
    reset_password_email_body { EmailTemplates.reset_password_body(reset_password_email_link) }
    email_auth_email_body { EmailTemplates.email_auth_body(email_auth_email_link) }
  end

  compile_assets
  include RouteHelpers

  require_relative 'routes/connections'

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
        r.redirect '/connections/goodreads/shelves'
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
