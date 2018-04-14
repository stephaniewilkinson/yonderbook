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
  include Capybara::DSL # it will bitch if you put this elsewhere and make it global

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
    visit "/"
  end
end
