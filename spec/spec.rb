ENV['RACK_ENV'] = 'test'

# require 'dotenv/load'
require 'minitest/autorun'
require 'minitest/pride'
require 'rack/test'

require_relative 'spec_helper'
require_relative '../app'

include Rack::Test::Methods

def app
  App
end

describe App do
  include Capybara::DSL

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
  it 'lets user log in' do
    visit '/'
    click_on 'Log in with goodreads'
    fill_in 'Email Address', with: 'what.happens@gmail.com'
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'Sign in'

    assert_text 'Your Goodreads Bookshelves'
  end
end
