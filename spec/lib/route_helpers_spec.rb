# frozen_string_literal: true

require_relative 'spec_helper'
require 'auth'
require 'cache'
require 'route_helpers'
require 'securerandom'
require 'shelf_loading'

describe RouteHelpers do
  # Create a minimal test class that includes RouteHelpers,
  # simulating the Roda app context with session and flash.
  let(:helper) do
    klass = Class.new do
      include RouteHelpers
      include ShelfLoading

      attr_accessor :session

      def flash
        @flash ||= {}
      end
    end
    obj = klass.new
    obj.session = {'session_id' => "test_#{SecureRandom.hex(8)}"}
    obj
  end

  describe '#store_goodreads_in_session' do
    it 'stores user_id, token, and secret in the cache' do
      credentials = {user_id: '12345', token: 'tok_abc', secret: 'sec_xyz'}
      helper.store_goodreads_in_session(credentials)

      assert_equal '12345', Cache.get(helper.session, :anon_goodreads_user_id)
      assert_equal 'tok_abc', Cache.get(helper.session, :anon_goodreads_token)
      assert_equal 'sec_xyz', Cache.get(helper.session, :anon_goodreads_secret)
    end
  end

  describe '#goodreads_session_present?' do
    it 'returns true and sets instance variables when credentials are cached' do
      Cache.set(helper.session, anon_goodreads_user_id: '12345', anon_goodreads_token: 'tok_abc', anon_goodreads_secret: 'sec_xyz')

      result = helper.goodreads_session_present?

      assert result
      assert_equal '12345', helper.instance_variable_get(:@goodreads_user_id)
      assert_kind_of OAuth::AccessToken, helper.instance_variable_get(:@anon_access_token)
    end

    it 'returns false when credentials are missing' do
      result = helper.goodreads_session_present?
      refute result
    end
  end

  describe '#require_goodreads_session' do
    it 'does not redirect when session credentials exist' do
      Cache.set(helper.session, anon_goodreads_user_id: '12345', anon_goodreads_token: 'tok_abc', anon_goodreads_secret: 'sec_xyz')

      request = Minitest::Mock.new
      helper.require_goodreads_session(request)

      assert_equal '12345', helper.instance_variable_get(:@goodreads_user_id)
    end
  end
  describe '#load_background_shelf_data' do
    # Real Roda redirects by throwing; this one throws too, so nothing after the
    # redirect runs, and records where it was going.
    let(:redirecting_helper) do
      helper.tap do |h|
        h.instance_variable_set :@shelf_name, 'to-read'
        h.define_singleton_method(:request) do
          Object.new.tap { |r| r.define_singleton_method(:redirect) { |path| throw :halt, path } }
        end
      end
    end

    def sid = redirecting_helper.session['session_id']

    it 'hands back the books once the background fetch is in' do
      books = [{title: 'A'}]
      Cache.set_by_id sid, goodreads_shelf_data: books, goodreads_shelf_ready: true
      redirecting_helper.session['pending_import_type'] = 'goodreads'

      assert_equal books, redirecting_helper.load_background_shelf_data
      assert_nil redirecting_helper.session['pending_import_type']
    end

    # A failed fetch still marks itself ready, and the loading page used to
    # reload into itself forever because nothing read the error.
    it 'stops the loading page and says why when the fetch failed' do
      Cache.set_by_id sid, goodreads_shelf_ready: true, goodreads_shelf_error: 'timed out'
      redirecting_helper.session['pending_import_type'] = 'goodreads'

      redirected_to = catch(:halt) { redirecting_helper.load_background_shelf_data }

      assert_equal '/goodreads/shelves', redirected_to
      assert_includes redirecting_helper.flash[:error], 'Goodreads'
      assert_nil redirecting_helper.session['pending_import_type'], 'a pending import would bring the loading page straight back'
      assert_nil Cache.get_by_id(sid, :goodreads_shelf_error)
    end
  end
end
