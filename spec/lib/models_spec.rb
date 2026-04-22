# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'

Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

require 'models/account'
require 'models/goodreads_connection'

describe Account do
  before do
    DB.tables.reject { |t| t == :schema_info }.each { |t| DB[t].truncate(cascade: true) }
    @account = Account.create(email: "test_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
  end

  describe '#goodreads_connected?' do
    it 'returns false when no connections exist' do
      refute @account.goodreads_connected?
    end

    it 'returns true when a connection exists' do
      GoodreadsConnection.create(user_id: @account.id, goodreads_user_id: 'gr123', access_token: 'tok', access_token_secret: 'sec')
      assert @account.goodreads_connected?
    end
  end

  describe '#goodreads_connection' do
    it 'returns nil when no connections exist' do
      assert_nil @account.goodreads_connection
    end

    it 'returns the most recent connection' do
      GoodreadsConnection.create(
        user_id: @account.id,
        goodreads_user_id: 'gr_old',
        access_token: 'tok1',
        access_token_secret: 'sec1',
        connected_at: Time.now - 3600
      )
      GoodreadsConnection.create(user_id: @account.id, goodreads_user_id: 'gr_new', access_token: 'tok2', access_token_secret: 'sec2', connected_at: Time.now)
      assert_equal 'gr_new', @account.goodreads_connection.goodreads_user_id
    end
  end
end

describe GoodreadsConnection do
  before do
    DB.tables.reject { |t| t == :schema_info }.each { |t| DB[t].truncate(cascade: true) }
    @account = Account.create(email: "test_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
  end

  describe 'validations' do
    it 'requires goodreads_user_id' do
      conn = GoodreadsConnection.new(user_id: @account.id, access_token: 'tok', access_token_secret: 'sec')
      refute conn.valid?
      assert_includes conn.errors[:goodreads_user_id], 'is required'
    end

    it 'requires access_token' do
      conn = GoodreadsConnection.new(user_id: @account.id, goodreads_user_id: 'gr123', access_token_secret: 'sec')
      refute conn.valid?
      assert_includes conn.errors[:access_token], 'is required'
    end

    it 'requires access_token_secret' do
      conn = GoodreadsConnection.new(user_id: @account.id, goodreads_user_id: 'gr123', access_token: 'tok')
      refute conn.valid?
      assert_includes conn.errors[:access_token_secret], 'is required'
    end

    it 'passes validation with all required fields' do
      conn = GoodreadsConnection.new(user_id: @account.id, goodreads_user_id: 'gr123', access_token: 'tok', access_token_secret: 'sec')
      assert conn.valid?
    end
  end

  describe 'timestamps' do
    it 'sets created_at, updated_at, and connected_at on create' do
      conn = GoodreadsConnection.create(user_id: @account.id, goodreads_user_id: 'gr123', access_token: 'tok', access_token_secret: 'sec')
      assert conn.created_at
      assert conn.updated_at
      assert conn.connected_at
    end

    it 'updates updated_at on save' do
      conn = GoodreadsConnection.create(user_id: @account.id, goodreads_user_id: 'gr123', access_token: 'tok', access_token_secret: 'sec')
      original = conn.updated_at
      sleep 0.01
      conn.update(access_token: 'new_tok')
      assert conn.updated_at >= original
    end
  end

  describe '#oauth_access_token' do
    it 'returns an OAuth::AccessToken' do
      conn = GoodreadsConnection.create(user_id: @account.id, goodreads_user_id: 'gr123', access_token: 'my_token', access_token_secret: 'my_secret')
      token = conn.oauth_access_token
      assert_instance_of OAuth::AccessToken, token
      assert_equal 'my_token', token.token
      assert_equal 'my_secret', token.secret
    end
  end
end
