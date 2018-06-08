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
    assert_includes last_response.body, 'Bookwyrm'
  end

  it 'responds to root' do
    get '/about'
    assert last_response.ok?
    assert_includes last_response.body, 'About'
  end

  it 'lets user log in and look at a shelf' do
    visit '/'
    click_on 'Log in with goodreads'
    fill_in 'Email Address', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'Sign in'
    assert_text 'to-read'
    click_on 'currently-reading'
    assert_text 'receive books'
    fill_in 'username', with: ENV.fetch('BOOKMOOCH_USERNAME')
    fill_in 'password', with: ENV.fetch('BOOKMOOCH_PASSWORD')
    click_on 'Authenticate'
    assert_text 'success'
    click_on 'Shelves'
    assert_text 'to-read'
    click_on 'didn-t-want-to-finish'
    assert_text 'download ebooks'
    fill_in 'zipcode', with: '94103'
    click_on 'Find a library'
    assert_text 'Libraries'
    click_on 'Check San Francisco'
    assert_text 'Lean In'
  end
end
