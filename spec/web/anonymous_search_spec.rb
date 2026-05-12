# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Anonymous search flow' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  describe 'GET /search-callback' do
    it 'redirects to / with error when no request token is cached' do
      visit '/search-callback'
      assert_current_path '/'
    end
  end
end
