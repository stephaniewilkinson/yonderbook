# frozen_string_literal: true

require_relative 'spec_helper'
require 'auth'
require 'cache'
require 'route_helpers'

describe RouteHelpers do
  # Create a minimal test class that includes RouteHelpers,
  # simulating the Roda app context with session and flash.
  let(:helper) do
    klass = Class.new do
      include RouteHelpers
      attr_accessor :session

      def flash
        @flash ||= {}
      end
    end
    obj = klass.new
    obj.session = {'session_id' => "test_#{rand(99999)}"}
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

  describe '#load_goodreads_from_session' do
    it 'returns true and sets instance variables when credentials are cached' do
      Cache.set(helper.session,
        anon_goodreads_user_id: '12345',
        anon_goodreads_token: 'tok_abc',
        anon_goodreads_secret: 'sec_xyz')

      result = helper.load_goodreads_from_session

      assert result
      assert_equal '12345', helper.instance_variable_get(:@goodreads_user_id)
      assert_kind_of OAuth::AccessToken, helper.instance_variable_get(:@anon_access_token)
    end

    it 'returns false when credentials are missing' do
      result = helper.load_goodreads_from_session
      refute result
    end
  end

  describe '#require_goodreads_session' do
    it 'does not redirect when session credentials exist' do
      Cache.set(helper.session,
        anon_goodreads_user_id: '12345',
        anon_goodreads_token: 'tok_abc',
        anon_goodreads_secret: 'sec_xyz')

      # If it doesn't raise/redirect, the guard passed
      request = Minitest::Mock.new
      helper.require_goodreads_session(request)

      assert_equal '12345', helper.instance_variable_get(:@goodreads_user_id)
    end
  end
end
