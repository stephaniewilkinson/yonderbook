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

  it 'lets user log in and see Goodreads connection options' do
    fake_email = "test_goodreads_user_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    # First create a Rodauth account
    puts 'Creating Rodauth account...'
    visit '/'
    click_link 'Sign Up'
    fill_in 'Email', with: fake_email
    fill_in 'Confirm Email', with: fake_email if page.has_field?('Confirm Email')
    fill_in 'Password', with: fake_password
    click_button 'Create Account'

    # Should be redirected to home page
    puts 'Checking for home page...'
    assert_text 'Welcome to Yonderbook!'

    # Try to connect with Goodreads - this will show the OAuth flow
    puts 'Starting Goodreads OAuth flow (attempt 1)...'
    click_link 'Connect with Goodreads'
    click_link 'Connect with Goodreads'
    sleep 2
    puts "Current URL: #{page.current_url}"
    click_button 'Sign in with email'
    sleep 2 # Wait for sign-in form to load

    puts 'Filling in credentials (attempt 1)...'
    fill_in 'email', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'password', with: ENV.fetch('GOODREADS_PASSWORD')
    find('#signInSubmit').click

    puts 'Visiting /home (attempt 1 complete)...'
    visit '/home'

    puts 'Starting Goodreads OAuth flow (attempt 2)...'
    click_link 'Connect with Goodreads'
    click_link 'Connect with Goodreads'
    sleep 2
    puts "Current URL: #{page.current_url}"
    click_button 'Sign in with email'
    sleep 2 # Wait for sign-in form to load

    puts 'Filling in credentials (attempt 2)...'
    fill_in 'email', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'password', with: ENV.fetch('GOODREADS_PASSWORD')
    find('#signInSubmit').click

    puts 'Visiting /home (attempt 2 complete)...'
    visit '/home'

    puts 'Starting Goodreads OAuth flow (attempt 3)...'
    click_link 'Connect with Goodreads'
    click_link 'Connect with Goodreads'
    sleep 2
    puts "Current URL: #{page.current_url}"
    click_button 'Sign in with email'
    sleep 2 # Wait for sign-in form to load

    puts 'Filling in credentials (attempt 3)...'
    fill_in 'email', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'password', with: ENV.fetch('GOODREADS_PASSWORD')
    find('#signInSubmit').click

    puts 'Visiting /auth/shelves...'
    visit '/auth/shelves'
    puts "Current URL: #{page.current_url}"
    assert_text 'Choose a shelf'
    all(:link, 'Stats')[2].click
    sleep 10
    assert_text 'Publication Years'
    click_on 'Shelves'
    assert_text 'to-read'
    first(:button, 'Get Books').click
    assert_text 'Choose a format'
    # Click eBooks link directly by visiting the overdrive path
    visit '/auth/shelves/to-read/overdrive'
    assert_text 'zip code'
    fill_in 'zipcode', with: '94103'
    click_on 'Find a library'
    sleep 10
    find('button[id="1683"]').click # Click the library selection button by consortium ID
    sleep 2  # Wait for OverDrive API to respond
    assert_text 'Available'
    click_on 'Unavailable'
    sleep 1  # Wait for the unavailable books section to load
    assert_text 'Unavailable' # Just verify we can see the unavailable section
    click_on 'Shelves'
    assert_text 'abandoned'
    all(:button, 'Get Books').find { |btn| btn.text == 'Get Books' }.click # Click Get Books for abandoned shelf
    assert_text 'Choose a format'
    within('.fixed') do # Within the modal
      find('a', text: 'By Mail').click
    end
    fill_in 'username', with: ENV.fetch('BOOKMOOCH_USERNAME')
    fill_in 'password', with: ENV.fetch('BOOKMOOCH_PASSWORD')
    click_button 'Authenticate'
    sleep 20 # Wait for BookMooch API to respond
    assert_text 'Success!'
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
    click_button 'Log In'

    # Should be redirected to home page after successful login
    assert_text 'Welcome to Yonderbook!'
    assert_text 'Connect with Goodreads'

    # Verify we're logged in by checking for logout link
    assert_link 'Logout'
    refute_link 'Login'
    refute_link 'Sign Up'
  end
end
