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

  describe 'page titles' do
    it 'has correct title format for root page' do
      get '/'
      assert_includes last_response.body, '<title>Yonderbook | Goodreads Libby Integration — Find Your Books Free at the Library</title>'
    end

    it 'appends Yonderbook suffix to page titles' do
      get '/about'
      assert_includes last_response.body, '<title>About | Yonderbook</title>'

      get '/faq'
      assert_includes last_response.body, '<title>FAQ | Yonderbook</title>'

      get '/how-it-works'
      assert_includes last_response.body, '<title>How It Works | Yonderbook</title>'

      get '/authenticate'
      assert_includes last_response.body, '<title>Log In | Yonderbook</title>'

      get '/sign-up'
      assert_includes last_response.body, '<title>Sign Up | Yonderbook</title>'
    end
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

    # Should redirect to check-email interstitial
    assert_text 'Check Your Email'
    assert_text fake_email

    # Manually verify the account so the user can log in
    verify_account(fake_email)

    # Log in with password (fallback method)
    password_login(fake_email, fake_password)

    # Should be redirected to home page after successful login
    assert_text 'Welcome back,'
    assert_text 'Connect Goodreads'

    # Wait for flash notification to auto-dismiss before testing logout
    sleep 5

    # Test logout by visiting logout path (no logout button in navbar anymore)
    visit '/logout'
    click_button 'Log Out' # Confirm logout

    # Should be back on the welcome page
    assert_text 'Log in'
    assert_text 'Create Your Account'

    # Test login with the same credentials
    click_link 'Log in'

    # Fill in password login form
    within('#password-login-form') do
      fill_in 'Email', with: fake_email
      fill_in 'Password', with: fake_password
      click_button 'Log In with Password'
    end

    # Should be redirected to home page after successful login
    assert_text 'Welcome back,'
    assert_text 'Connect Goodreads'

    # Verify we're logged in by checking navbar links
    assert_link 'Account'
    refute_link 'Login'
    refute_link 'Sign Up'
    sleep 2 # Give Selenium time to clean up session before next test
  end

  it 'connects Goodreads via OAuth and browses shelves' do
    fake_email = "test_goodreads_user_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # First create a Rodauth account
    visit '/'
    click_link 'Sign Up'
    fill_in 'Email', with: fake_email
    fill_in 'Confirm Email', with: fake_email if page.has_field?('Confirm Email')
    fill_in 'Password', with: fake_password
    click_button 'Create Account'

    # Manually verify the account so the user can log in
    verify_account(fake_email)

    # Log in with the verified account
    password_login(fake_email, fake_password)

    # Should be redirected to home page
    assert_text 'Welcome back,'

    # Try to connect with Goodreads - OAuth flow requires 3 attempts to bypass Amazon CVF
    3.times do
      click_link 'Connect Goodreads'
      click_link 'Connect with Goodreads'
      sleep 2

      # Check if already authenticated (redirected to /goodreads/shelves)
      break if page.current_url.include?('/goodreads/shelves')

      # Only try to sign in if we're on Goodreads sign-in page
      if page.has_button?('Sign in with email', wait: 2)
        click_button 'Sign in with email'
        sleep 2

        if page.has_field?('email', wait: 2) && page.has_field?('password', wait: 2)
          fill_in 'email', with: ENV.fetch('GOODREADS_EMAIL')
          fill_in 'password', with: ENV.fetch('GOODREADS_PASSWORD')
          find('#signInSubmit').click
          sleep 5 # Wait for CVF/redirect
        end

        # Check if OAuth completed after sign-in
        break if page.current_url.include?('/goodreads/shelves')
      end

      visit '/home' unless page.current_url.include?('/goodreads/shelves')
    end

    # Final visit to get OAuth tokens
    visit '/goodreads/shelves'
    assert_text 'Choose a shelf'
    sleep 2
  end

  it 'shows shelf stats for a seeded Goodreads user' do
    seed_goodreads_user
    visit '/goodreads/shelves'
    assert_text 'Choose a shelf'

    all(:link, 'Stats')[2].click
    sleep 10
    assert_text 'Publication Years'
    sleep 2
  end

  it 'searches OverDrive libraries for a seeded Goodreads user' do
    seed_goodreads_user
    visit '/goodreads/shelves/zora/overdrive'
    assert_text 'zip code'

    fill_in 'zipcode', with: '94103'
    click_on 'Find a library'
    sleep 10
    first('button[type="submit"][name="action"]').click
    sleep 15
    assert page.has_text?('Available', wait: 30)
    click_on 'Unavailable'
    sleep 1
    assert_text 'Unavailable'
    sleep 2
  end

  it 'shows BookMooch on the connections page with education and Goodreads requirement' do
    seed_goodreads_user
    visit '/connections'

    # BookMooch card should be visible with educational content
    assert_text 'BookMooch'
    assert_text 'book trading'
    assert_text 'BookMooch account'

    # Should explain it requires Goodreads
    # Since Goodreads IS connected, the sync button should be active
    click_link 'Sync to BookMooch'

    # Should land on shelves page in bookmooch mode
    assert_text 'Choose a shelf'
    sleep 2
  end

  it 'shows BookMooch requires Goodreads when not connected' do
    fake_email = "test_bm_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    visit '/'
    click_link 'Sign Up'
    fill_in 'Email', with: fake_email
    fill_in 'Confirm Email', with: fake_email if page.has_field?('Confirm Email')
    fill_in 'Password', with: fake_password
    click_button 'Create Account'
    verify_account(fake_email)
    password_login(fake_email, fake_password)

    visit '/connections'

    # BookMooch card should be visible but indicate Goodreads is needed
    assert_text 'BookMooch'
    assert_text 'Connect Goodreads first'
    sleep 2
  end

  it 'imports books to BookMooch via connections page' do
    seed_goodreads_user
    visit '/connections'

    # Navigate to BookMooch through connections page
    click_link 'Sync to BookMooch'
    assert_text 'Choose a shelf'

    # Click the BookMooch button for the abandoned shelf (small shelf, faster import)
    find('a[href="shelves/abandoned/bookmooch"]').click

    if page.has_text?('BookMooch appears to be down', wait: 5)
      # BookMooch is currently unreachable - verify the user sees the warning
      assert_text 'BookMooch appears to be down'
      assert_text 'Choose a shelf'
    else
      fill_in 'username', with: ENV.fetch('BOOKMOOCH_USERNAME')
      fill_in 'password', with: ENV.fetch('BOOKMOOCH_PASSWORD')
      click_button 'Authenticate'
      assert_text 'Importing Books to BookMooch'
      sleep 120
      assert_text 'Success!'
    end
    sleep 2
  end
end
