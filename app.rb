# frozen_string_literal: true

system 'roda-parse_routes', '-f', 'routes.json', __FILE__

require 'area'
require 'rack/host_redirect'
require 'roda'
require 'securerandom'
require 'sentry-ruby'
require 'tilt'
# require 'zbar'

require_relative 'lib/auth'
require_relative 'lib/bookmooch'
require_relative 'lib/cache'
require_relative 'lib/database'
require_relative 'lib/email'
require_relative 'lib/goodreads'
require_relative 'lib/models'
require_relative 'lib/overdrive'
require_relative 'lib/websockets'

class App < Roda
  use Sentry::Rack::CaptureExceptions
  use Rack::HostRedirect, 'bookmooch.herokuapp.com' => 'yonderbook.com'

  plugin :head
  plugin :assets, css: 'styles.css'
  plugin :assets_preloading
  plugin :public, root: 'assets'
  plugin :flash
  plugin :sessions, secret: ENV.fetch('SESSION_SECRET')
  plugin :route_csrf
  plugin :slash_path_empty
  plugin :render
  plugin :partials
  plugin :default_headers, 'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'
  plugin :websockets

  # Rodauth configuration with email verification and password reset
  plugin :rodauth do
    db DB
    enable :login, :logout, :create_account, :verify_account, :reset_password
    hmac_secret ENV.fetch('SESSION_SECRET')

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
    account_status_column :status_id
    account_open_status_value 2 # Verified status
    account_unverified_status_value 1 # Unverified status

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
    logout_redirect '/'
    verify_account_redirect '/home'

    # Redirect to login after account creation (user needs to verify email first)
    create_account_redirect '/authenticate'

    # Email configuration
    email_from 'app@yonderbook.com'
    email_subject_prefix '[Yonderbook] '

    # Send emails using Resend
    send_email do |email|
      EmailService.send_email(to: email.to.first, subject: email.subject, html: email.html_part&.body&.to_s || email.body.to_s)
    end

    # Custom error messages for better UX
    no_matching_login_message 'No account exists with that email. Please create an account.'
    reset_password_request_error_flash 'There was an error requesting a password reset. Please make sure the email is correct and that you have an account.'

    # Success notifications
    create_account_notice_flash 'Account created! Check your email to verify your account before logging in.'
    reset_password_email_sent_notice_flash 'We sent you a password reset link to your email. Click the link in the email to finish resetting your password.'
    reset_password_email_sent_redirect '/authenticate'

    # Email subjects
    verify_account_email_subject 'Verify Your Yonderbook Account'
    reset_password_email_subject 'Reset Your Yonderbook Password'
  end

  compile_assets

  # Helper methods
  def fetch_and_cache_request_token
    Auth.fetch_request_token.tap { |token| Cache.set(session, request_token: token) if token }
  rescue StandardError
    nil
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

  # TODO: figure out how to reroute 404s to /
  route do |r|
    r.public
    r.assets

    # Rodauth routes (login, create-account, etc.)
    r.rodauth

    # Load current user for authenticated routes
    @user = Account[rodauth.session_value] if rodauth.logged_in?

    session['session_id'] ||= SecureRandom.uuid

    # route: WebSocket /ws/bookmooch/:session_id
    r.on 'ws', 'bookmooch', String do |session_id|
      r.websocket { |connection| Websockets.handle_bookmooch(connection, session_id) }
    end

    # route: GET /
    r.root do
      request_token = fetch_and_cache_request_token
      @auth_url = request_token&.authorize_url
      view 'welcome'
    end

    r.is 'login' do
      request_token = Cache.get session, :request_token
      # TODO: this is blocking people who are already logged in but not a huge deal
      unless request_token
        flash[:error] = "Click 'login' again please"
        r.redirect '/'
      end

      # route: GET /login
      r.get do
        # User must be logged in to save Goodreads connection
        unless @user
          flash[:error] = 'Please log in first before connecting Goodreads'
          r.redirect '/'
        end

        # Save Goodreads connection to database (user_id passed to fetch_user)
        Goodreads.fetch_user request_token, @user.id
        @user.refresh # Reload from database to get new connection

        r.redirect '/connections/goodreads/shelves'
      rescue OAuth::Unauthorized
        flash[:error] = 'Fetched details! Click login'
        r.redirect '/'
      end
    end

    # route: GET /about
    r.is('about') { r.get { view 'about' } }

    r.on 'account' do
      # route: POST /account/disconnect-goodreads
      r.post 'disconnect-goodreads' do
        rodauth.require_login
        check_csrf!

        # Delete Goodreads connection
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

    r.on 'connections' do
      # route: GET /connections
      r.get true do
        @goodreads_connection = @user&.goodreads_connection
        view 'connections'
      end

      r.on 'goodreads' do
        # route: GET /connections/goodreads
        r.get true do
          r.redirect '/home' if @user&.goodreads_connected?
          # Always fetch a fresh request token (they expire and can only be used once)
          request_token = fetch_and_cache_request_token
          @auth_url = request_token&.authorize_url
          view 'connect_goodreads'
        end

        # Require Goodreads connection for shelves
        r.on 'shelves' do
          unless @user&.goodreads_connected?
            flash[:error] = 'Please connect your Goodreads account first'
            r.redirect '/connections/goodreads'
          end

          load_goodreads_connection

          # route: GET /connections/goodreads/shelves
          r.get true do
            @shelves = Goodreads.fetch_shelves @goodreads_user_id
            view 'shelves/index'
          end

          # TODO: change this so I'm not passing stuff back and forth from cache unnecessarily
          r.on String do |shelf_name|
            @shelf_name = shelf_name
            Cache.set session, shelf_name: @shelf_name

            @book_info = cached_or_fetch(@shelf_name.to_sym) do
              access_token = @goodreads_connection.oauth_access_token
              Goodreads.get_books @shelf_name, @goodreads_user_id, access_token
            end

            # route: GET /connections/goodreads/shelves/:id
            r.get true do
              @women, @men, @andy = Goodreads.get_gender @book_info
              @histogram_dataset = Goodreads.plot_books_over_time @book_info
              @ratings = Goodreads.rating_stats @book_info

              view 'shelves/show'
            end

            r.on 'bookmooch' do
              # route: GET /connections/goodreads/shelves/:id/bookmooch
              r.get true do
                view 'shelves/bookmooch'
              end

              # route: POST /connections/goodreads/shelves/:id/bookmooch?username=foo&password=baz
              r.post do
                # Store job params in cache for WebSocket to pick up
                Cache.set_by_id(
                  session['session_id'],
                  bookmooch_book_info: @book_info,
                  bookmooch_username: r.params['username'],
                  bookmooch_password: r.params['password']
                )

                # Redirect to progress page which will connect via WebSocket
                r.redirect 'bookmooch/progress'
              end

              # route: GET /connections/goodreads/shelves/:id/bookmooch/progress
              r.get 'progress' do
                @session_id = session['session_id']
                view 'bookmooch_progress'
              end

              # route: GET /connections/goodreads/shelves/:id/bookmooch/results
              r.get 'results' do
                @books_added = Cache.get session, :books_added
                books_failed = Cache.get session, :books_failed

                # Separate books that failed due to missing ISBN vs other reasons
                @books_failed_no_isbn, @books_failed = books_failed.partition { |book| book[:isbn].nil? || book[:isbn].empty? }

                view 'bookmooch'
              end
            end

            r.is 'overdrive' do
              # TODO: have browser get their location
              # route: GET /connections/goodreads/shelves/:id/overdrive
              r.get true do
                view 'shelves/overdrive'
              end

              # route: POST /connections/goodreads/shelves/:id/overdrive?consortium=1047
              r.post do
                overdrive = Overdrive.new(@book_info, r.params['consortium'])
                titles = overdrive.fetch_titles_availability
                Cache.set(session, titles:, collection_token: overdrive.collection_token, website_id: overdrive.website_id, library_url: overdrive.library_url)
                r.redirect '/connections/goodreads/availability'
              end
            end
          end
        end

        r.is 'availability' do
          unless @user&.goodreads_connected?
            flash[:error] = 'Please connect your Goodreads account first'
            r.redirect '/connections/goodreads'
          end

          load_goodreads_connection

          # route: GET /connections/goodreads/availability
          r.get do
            @titles = Cache.get session, :titles
            @collection_token = Cache.get session, :collection_token
            @website_id = Cache.get session, :website_id
            @library_url = Cache.get session, :library_url

            unless @titles
              flash[:error] = 'Please choose a shelf first'
              r.redirect 'shelves'
            end

            # Sort each category by most recently added to Goodreads shelf (descending)
            @available_books = sort_by_date_added(@titles.select { |a| a.copies_available.positive? })
            @waitlist_books = sort_by_date_added(@titles.select { |a| a.copies_available.zero? && a.copies_owned.positive? })
            @no_isbn_books = sort_by_date_added(@titles.select(&:no_isbn))
            @unavailable_books = sort_by_date_added(@titles.select { |a| a.copies_owned.zero? && !a.no_isbn })
            view 'availability'
          end
        end

        # TODO: add library logos to the cards in the views
        r.is 'library' do
          unless @user&.goodreads_connected?
            flash[:error] = 'Please connect your Goodreads account first'
            r.redirect '/connections/goodreads'
          end

          load_goodreads_connection

          # route: POST /connections/goodreads/library?zipcode=90029
          r.post do
            @shelf_name = Cache.get session, :shelf_name
            zip = r.params['zipcode']

            if zip.empty?
              flash[:error] = 'You need to enter a zip code'
              r.redirect "shelves/#{@shelf_name}/overdrive"
            end

            unless zip.to_latlon
              flash[:error] = 'please try a different zip code'
              r.redirect "shelves/#{@shelf_name}/overdrive"
            end

            @local_libraries = Overdrive.local_libraries zip.delete ' '
            Cache.set session, libraries: @local_libraries
            r.redirect '/connections/goodreads/library'
          end

          # route: GET /connections/goodreads/library
          r.get do
            @shelf_name = Cache.get session, :shelf_name
            @local_libraries = Cache.get session, :libraries
            # TODO: see if we can bring the person back to the choose a library stage rather than all the way back to choose a shelf
            unless @local_libraries
              flash[:error] = 'Please choose a shelf first'
              r.redirect 'shelves'
            end
            view 'library'
          end
        end
      end
    end
  rescue OAuth::Unauthorized, StandardError, ScriptError => e
    # Always send to Sentry first
    Sentry.capture_exception(e)

    # In production, redirect gracefully; in dev/test, raise to see full error
    raise e unless ENV['RACK_ENV'] == 'production'

    r.redirect '/'
  end
end
