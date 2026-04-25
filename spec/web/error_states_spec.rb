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
    fake_email = "test_wrongpw_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    visit '/sign-up'
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Create Account'
    verify_account(fake_email)

    visit '/authenticate'
    within('#password-login-form') do
      fill_in 'Email', with: fake_email
      fill_in 'Password', with: 'WrongPassword999!'
      click_button 'Log In with Password'
    end

    assert_text 'invalid password'
    sleep 2
  end

  it 'shows error for non-existent account login' do
    visit '/authenticate'
    within('#password-login-form') do
      fill_in 'Email', with: 'nobody@example.com'
      fill_in 'Password', with: 'Whatever123!'
      click_button 'Log In with Password'
    end

    assert_text 'No account exists with that email'
    sleep 2
  end

  it 'rejects signup when honeypot field is filled in' do
    bot_email = "bot_#{Time.now.to_i}@example.com"
    account_count = DB[:accounts].count

    visit '/sign-up'
    fill_in 'Email', with: bot_email
    fill_in 'Password', with: 'BotPassword123!'
    page.execute_script("document.getElementById('name').value = 'Bot McBotface'")
    click_button 'Create Account'

    assert_current_path '/check-email'
    assert_equal account_count, DB[:accounts].count
  end

  it 'returns ok from health endpoint' do
    get '/health'
    assert last_response.ok?
    assert_equal 'ok', last_response.body
  end

  it 'redirects to connect goodreads when accessing shelves without connection' do
    fake_email = "test_noshelves_#{Time.now.to_i}@example.com"
    fake_password = 'SecurePassword123!'

    visit '/sign-up'
    fill_in 'Email', with: fake_email
    fill_in 'Password', with: fake_password
    click_button 'Create Account'
    verify_account(fake_email)
    password_login(fake_email, fake_password)

    visit '/goodreads/shelves'
    assert_text 'Please connect your Goodreads account first'
    sleep 2
  end
end
