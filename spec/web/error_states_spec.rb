# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Error states' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let :app do
    App
  end

  it 'redirects to login when accessing /home without auth' do
    get '/home'
    assert last_response.redirect?
    assert_includes last_response.headers['Location'], '/authenticate'
  end

  it 'redirects to login when accessing /account without auth' do
    get '/account'
    assert last_response.redirect?
    assert_includes last_response.headers['Location'], '/authenticate'
  end

  it 'shows error for wrong password login' do
    email, = create_account_direct

    visit '/authenticate'
    within('#password-login-form') do
      fill_in 'Email', with: email
      fill_in 'Password', with: 'WrongPassword999!'
      click_button 'Log In with Password'
    end

    assert_text 'invalid password'
  end

  it 'shows error for non-existent account login' do
    visit '/authenticate'
    within('#password-login-form') do
      fill_in 'Email', with: 'nobody@example.com'
      fill_in 'Password', with: 'Whatever123!'
      click_button 'Log In with Password'
    end

    assert_text 'No account exists with that email'
  end

  it 'returns ok from health endpoint' do
    get '/health'
    assert last_response.ok?
    assert_equal 'ok', last_response.body
  end

  it 'redirects to connect goodreads when accessing shelves without connection' do
    email, password = create_account_direct
    password_login(email, password)

    visit '/goodreads/shelves'
    assert_text 'Please connect your Goodreads account first'
  end

  it 'handles /connections without auth gracefully' do
    visit '/connections'
    assert page.has_text?('Yonderbook')
  end

  it 'shows check-email page with fallback when no pending email in session' do
    get '/check-email'
    assert last_response.ok?
    assert_includes last_response.body, 'your email'
  end

  it 'redirects to root for unknown routes under /goodreads' do
    get '/goodreads/nonexistent'
    refute_equal 500, last_response.status
  end

  it 'disconnects Goodreads connection for authenticated user' do
    email, password = create_account_direct
    password_login(email, password)

    # Add a Goodreads connection directly
    account = DB[:accounts].where(email: email).first
    DB[:goodreads_connections].insert(user_id: account[:id], goodreads_user_id: 'gr_test_disconnect', access_token: 'tok', access_token_secret: 'sec')

    assert DB[:goodreads_connections].where(user_id: account[:id]).any?

    # Visit account page and disconnect (accept confirmation dialog)
    visit '/account'
    accept_confirm do
      click_button 'Disconnect Goodreads'
    end

    assert_text 'removed'
    refute DB[:goodreads_connections].where(user_id: account[:id]).any?
  end

  it 'redirects from /libraries without auth' do
    get '/libraries'
    assert last_response.redirect?
  end

  it 'redirects from /goodreads/availability when no titles cached' do
    seed_goodreads_user
    visit '/goodreads/availability'
    assert_text 'Please choose a shelf first'
  end
end
