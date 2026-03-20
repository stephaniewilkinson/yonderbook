# frozen_string_literal: true

RODAUTH_CONFIG = proc do
  db DB
  enable :login, :logout, :create_account, :verify_account, :reset_password, :lockout
  hmac_secret SESSION_SECRET

  # Base URL for email links
  base_url ENV.fetch('BASE_URL', 'https://localhost:9292')

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

  # Rate limiting - lock account after 10 failed login attempts
  max_invalid_logins 10
  unlock_account_email_subject 'Unlock Your Yonderbook Account'

  # Email subjects
  verify_account_email_subject 'Verify Your Yonderbook Account'
  reset_password_email_subject 'Reset Your Yonderbook Password'
end
