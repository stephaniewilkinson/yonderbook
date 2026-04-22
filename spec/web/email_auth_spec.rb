# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Magic link and email auth' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let :app do
    App
  end

  it 'shows check-email page after account creation with correct email' do
    fake_email = "test_checkemail_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    visit '/sign-up'
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Create Account'

    # Should redirect to check-email interstitial
    assert_text 'Check Your Email'
    assert_text fake_email
    assert_text 'spam or promotions'
    assert_link 'Resend verification email'
    assert_link 'Log in'
    sleep 2
  end

  it 'shows the login page with magic link as primary and password as fallback' do
    visit '/authenticate'

    # Magic link form is primary
    assert_button 'Send Me a Login Link'
    assert_text 'or use your password'

    # Password form is fallback
    assert_button 'Log In with Password'
    assert_link 'Forgot password?'
    assert_link 'Sign up'
    sleep 2
  end

  it 'sends a magic link email when requesting email auth' do
    fake_email = "test_magiclink_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # Create and verify an account first
    visit '/sign-up'
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Create Account'
    verify_account(fake_email)

    # Request a magic link
    visit '/authenticate'
    within('#magic-link-form') do
      fill_in 'Email', with: fake_email
      click_button 'Send Me a Login Link'
    end

    # Should show confirmation flash
    assert_text 'Check your email for a login link'

    # Verify the email auth key was created in the database
    account = DB[:accounts].where(email: fake_email).first
    key_row = DB[:account_email_auth_keys].where(id: account[:id]).first
    assert key_row, 'Expected email_auth_key to be created'
    assert key_row[:key], 'Expected key to have a value'
    sleep 2
  end

  it 'logs in via magic link token' do
    fake_email = "test_magictoken_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # Create and verify an account
    visit '/sign-up'
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Create Account'
    verify_account(fake_email)

    # Request a magic link
    visit '/authenticate'
    within('#magic-link-form') do
      fill_in 'Email', with: fake_email
      click_button 'Send Me a Login Link'
    end

    # Build the magic link URL from the database key (wait for async creation)
    account = DB[:accounts].where(email: fake_email).first
    key_row = nil
    10.times do
      key_row = DB[:account_email_auth_keys].where(id: account[:id]).first
      break if key_row

      sleep 0.2
    end
    assert key_row, 'Expected email_auth_key to be created'

    visit "/email-auth?key=#{account[:id]}_#{key_row[:key]}"
    click_button 'Log In'

    # Should be logged in and redirected to home
    assert_current_path '/home'
    sleep 2
  end

  it 'verifies account and auto-logs in when clicking verification link' do
    fake_email = "test_autologin_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # Create account (unverified)
    visit '/sign-up'
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Create Account'

    # Build the verification URL from the database key
    account = nil
    key_row = nil
    10.times do
      account = DB[:accounts].where(email: fake_email).first
      key_row = DB[:account_verification_keys].where(id: account[:id]).first if account
      break if key_row

      sleep 0.1
    end
    assert key_row, 'Expected verification key to be created'

    visit "/verify-account?key=#{account[:id]}_#{key_row[:key]}"
    click_button 'Verify Account'

    # Should be auto-logged in and redirected to home (verify_account_autologin? true)
    assert_current_path '/home'
    sleep 2
  end
end
