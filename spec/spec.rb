ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require_relative '../app'
require_relative 'spec_helper'

include Rack::Test::Methods

def app
  Unreloader
end

describe App do
  it 'responds to root' do
    get '/'
    assert last_response.ok?
    assert_includes last_response.body, 'Bookwyrm'
  end
end
