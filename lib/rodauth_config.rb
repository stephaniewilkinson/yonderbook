# frozen_string_literal: true

require 'rodauth'

class RodauthConfig < Rodauth::Auth
  configure do
    db DB
    enable :login, :logout, :create_account, :verify_account, :reset_password, :lockout
    enable :email_auth, :argon2, :update_password_hash, :active_sessions
    enable :session_expiration, :disallow_common_passwords, :close_account

    # "Delete my account" means delete (#1416), not Rodauth's default of marking
    # it closed and keeping the row. goodreads_connections, imported_books and
    # bookmooch_imports go with it by ON DELETE CASCADE.
    delete_account_on_close? true
    close_account_redirect '/'
    # password_hash_table is pointed at accounts itself (below), so Rodauth's
    # close_account -- which deletes the row from a separate password-hash
    # table -- deleted the account row before after_close_account could run.
    # Here the hash goes with the account, so only mark it closed.
    # (account_password_hash_column is Rodauth's own way to keep the hash on
    # accounts; switching to it would remove the need for this.)
    auth_class_eval do
      def close_account
        update_account(account_status_column => account_closed_status_value)
      end
    end
    close_account_notice_flash 'Your account and everything stored with it have been deleted.'

    # Rodauth's own key tables reference accounts without a cascade, and foreign
    # keys are enforced (lib/database.rb), so a leftover verification,
    # password-reset or sign-in-link key would block the delete. Runs inside
    # the same transaction, before delete_account.
    after_close_account do
      %i[
        account_verification_keys
        account_password_reset_keys
        account_email_auth_keys
        account_login_failures
        account_lockouts
      ].each { |table| db[table].where(id: account_id).delete }
      db[:account_active_session_keys].where(account_id: account_id).delete
    end

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

    # signup counts form submits; only a verified account is a real one. #1411
    after_verify_account do
      flash['fathom_event'] = 'account_verified'
    end

    # Returning account holders, by password or magic link. #1411
    after_login do
      flash['fathom_event'] = 'logged_in'
    end

    # Session expiration: 30 min inactivity, 24 hour max lifetime
    session_inactivity_timeout 1800
    max_session_lifetime 86_400

    # Redirect to check-email interstitial after account creation
    create_account_redirect '/check-email'

    # Strip whitespace from email before account creation
    before_create_account do
      account[login_column] = account[login_column].strip

      # Honeypot: bots fill in the hidden "name" field, humans don't see it
      redirect '/check-email' unless param('name').empty?
    end

    # Store email in session after account creation for the interstitial page
    after_create_account do
      session['pending_email'] = account[login_column]

      # A visitor can connect Goodreads before signing up. Those credentials sit
      # in the session cache, which dies with the session, so copy them onto the
      # account or the connection is silently lost at the moment they commit.
      #
      # The cache entries stay put: they still have to verify their email, and
      # the anonymous flow has to keep working until they do.
      goodreads_user_id = Cache.get(session, :anon_goodreads_user_id)
      token = Cache.get(session, :anon_goodreads_token)
      secret = Cache.get(session, :anon_goodreads_secret)

      if goodreads_user_id && token && secret
        begin
          Goodreads.save_goodreads_connection(account[account_id_column], goodreads_user_id, token, secret)
        rescue StandardError => e
          # Never cost someone the account they actually asked for -- they can
          # reconnect from /connections.
          Sentry.capture_exception(e)
        end
      end

      # The same for a library uploaded before signing up (#1414). It is only in
      # the session cache, which the login after verification replaces, so this
      # is the one moment it can be kept.
      if (library = Cache.get(session, :anonymous_library))
        begin
          ImportedBook.replace_library(account[account_id_column], library, max: ImportRoutes::MAX_IMPORT_BOOKS)
        rescue StandardError => e
          Sentry.capture_exception(e)
        end
      end
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
    reset_password_notice_flash 'Your password has been reset'
    reset_password_redirect '/authenticate'
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
end
