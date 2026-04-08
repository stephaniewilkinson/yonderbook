# frozen_string_literal: true

require 'rodauth'

class RodauthConfig < Rodauth::Auth
  configure do
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
end
