# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Authentication flows' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let :app do
    App
  end

  describe 'password reset' do
    it 'completes the full password reset flow' do
      email, = create_account_direct
      new_password = 'NewSecurePassword456!'

      # Request password reset
      visit '/reset-password-request'
      fill_in 'Email', with: email
      click_button 'Send Password Reset Email'

      assert_text 'password reset link'

      # Build the reset URL from the database key
      account = DB[:accounts].where(email: email).first
      key_row = nil
      10.times do
        key_row = DB[:account_password_reset_keys].where(id: account[:id]).first
        break if key_row

        sleep 0.1
      end
      assert key_row, 'Expected password reset key to be created'

      # Visit the reset link and set new password
      visit "/reset-password?key=#{account[:id]}_#{key_row[:key]}"
      fill_in 'Password', with: new_password
      click_button 'Reset Password'

      # Log in with the new password
      password_login(email, new_password)
      assert_text 'Welcome back,'
    end

    it 'shows error for non-existent email on password reset request' do
      visit '/reset-password-request'
      fill_in 'Email', with: 'nobody_exists@example.com'
      click_button 'Send Password Reset Email'

      assert_text 'error'
    end
  end

  describe 'account lockout' do
    it 'locks account after max failed login attempts' do
      email, password = create_account_direct

      # Simulate 9 failed logins via DB (avoids slow Capybara visits)
      account = DB[:accounts].where(email: email).first
      DB[:account_login_failures].insert(id: account[:id], number: 9)

      # One more failed attempt triggers lockout creation
      visit '/authenticate'
      within('#password-login-form') do
        fill_in 'Email', with: email
        fill_in 'Password', with: 'WrongPassword!'
        click_button 'Log In with Password'
      end

      # Verify lockout record exists in database
      lockout = DB[:account_lockouts].where(id: account[:id]).first
      assert lockout, 'Expected account lockout record to exist'

      # Now try with correct password - should still be locked
      visit '/authenticate'
      within('#password-login-form') do
        fill_in 'Email', with: email
        fill_in 'Password', with: password
        click_button 'Log In with Password'
      end

      assert_text(/locked|unlock/i)
    end
  end

  describe 'session expiration' do
    it 'redirects to login after session expires' do
      get '/home'
      assert last_response.redirect?
      assert_includes last_response.headers['Location'], '/authenticate'
    end
  end
end
