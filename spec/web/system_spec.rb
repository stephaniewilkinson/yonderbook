# frozen_string_literal: true

require_relative 'spec_helper'

describe App do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let :app do
    App
  end

  it 'responds to root' do
    get '/'
    assert last_response.ok?
    assert_includes last_response.body, 'Yonderbook'
  end

  it 'responds to /about' do
    get '/about'
    assert last_response.ok?
    assert_includes last_response.body, 'About'
  end

  it 'tests the complete Rodauth authentication flow' do
    fake_email = "test_user_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # Test account creation
    visit '/'
    click_link 'Sign Up'

    # Fill in sign up form (handle email confirmation if present)
    fill_in 'Email', with: fake_email
    fill_in 'Confirm Email', with: fake_email if page.has_field?('Confirm Email')
    fill_in 'Password', with: fake_password
    click_button 'Create Account'

    # Should be redirected to home page after successful account creation
    assert_text 'Welcome to Yonderbook!'
    assert_text 'Connect with Goodreads'

    # Test logout
    click_link 'Logout'

    # Should be back on the welcome page
    assert_text 'Yonderbook'

    # Visit home page to force a page reload and check logged out state
    visit '/'
    assert_text 'Already have an account? Log in'
    assert_text 'Create Your Account'

    # Test login with the same credentials
    click_link 'Already have an account? Log in'

    # Fill in login form
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Login'

    # Should be redirected to home page after successful login
    assert_text 'Welcome to Yonderbook!'
    assert_text 'Connect with Goodreads'

    # Verify we're logged in by checking for logout link
    assert_link 'Logout'
    refute_link 'Login'
    refute_link 'Sign Up'
  end

  it 'lets user log in and see Goodreads connection options' do
    fake_email = "test_goodreads_user_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # First create a Rodauth account
    visit '/'
    click_link 'Sign Up'
    fill_in 'Email', with: fake_email
    fill_in 'Confirm Email', with: fake_email if page.has_field?('Confirm Email')
    fill_in 'Password', with: fake_password
    click_button 'Create Account'

    # Should be redirected to home page
    assert_text 'Welcome to Yonderbook!'

    # Try to connect with Goodreads - this will show the OAuth flow
    click_link 'Connect with Goodreads'

    # Since Goodreads API is deprecated, we just verify the page loads
    # and shows appropriate content for connection attempt
    assert_text 'Goodreads'

    # Test that the home page properly handles the broken OAuth
    visit '/home'
    assert_text 'Welcome to Yonderbook!'

    # Verify that user can navigate without OAuth working
    visit '/about'
    assert_text 'About'
  end
end
