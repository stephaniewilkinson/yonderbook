# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'

Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

require 'models/account'
require 'models/bookmooch_import'
require 'models/goodreads_connection'

describe Account do
  before do
    DB.run('PRAGMA foreign_keys = OFF')
    DB.tables.each { |t| DB[t].delete }
    DB.run('PRAGMA foreign_keys = ON')
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
    DB.run('PRAGMA foreign_keys = OFF')
    DB.tables.each { |t| DB[t].delete }
    DB.run('PRAGMA foreign_keys = ON')
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

describe BookmoochImport do
  before do
    DB.run('PRAGMA foreign_keys = OFF')
    DB.tables.each { |t| DB[t].delete }
    DB.run('PRAGMA foreign_keys = ON')
    @account = Account.create(email: "test_bm_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
  end

  describe '.already_imported_isbns' do
    it 'returns a set of imported ISBNs for the user' do
      BookmoochImport.create(user_id: @account.id, isbn: '111')
      BookmoochImport.create(user_id: @account.id, isbn: '222')
      result = BookmoochImport.already_imported_isbns(@account.id)
      assert_instance_of Set, result
      assert_includes result, '111'
      assert_includes result, '222'
    end

    it 'returns empty set when no imports exist' do
      result = BookmoochImport.already_imported_isbns(@account.id)
      assert_empty result
    end

    it 'does not include ISBNs from other users' do
      other = Account.create(email: "other_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
      BookmoochImport.create(user_id: other.id, isbn: '999')
      result = BookmoochImport.already_imported_isbns(@account.id)
      refute_includes result, '999'
    end
  end

  describe '.record_imports' do
    it 'inserts new import records' do
      books = [{isbn: '111', bookmooch_isbn: '111'}, {isbn: '222', bookmooch_isbn: '333'}]
      BookmoochImport.record_imports(@account.id, books, shelf_name: 'read')
      assert_equal 2, BookmoochImport.where(user_id: @account.id).count
    end

    it 'skips books with nil or empty ISBN' do
      books = [{isbn: nil}, {isbn: ''}, {isbn: '111', bookmooch_isbn: '111'}]
      BookmoochImport.record_imports(@account.id, books, shelf_name: 'read')
      assert_equal 1, BookmoochImport.where(user_id: @account.id).count
    end

    it 'updates existing records on conflict instead of duplicating' do
      BookmoochImport.create(user_id: @account.id, isbn: '111', shelf_name: 'to-read')
      books = [{isbn: '111', bookmooch_isbn: '111'}]
      BookmoochImport.record_imports(@account.id, books, shelf_name: 'read')
      assert_equal 1, BookmoochImport.where(user_id: @account.id).count
      assert_equal 'read', BookmoochImport.where(user_id: @account.id, isbn: '111').first[:shelf_name]
    end
  end

  describe '.clear_imports' do
    it 'deletes all imports for the user' do
      BookmoochImport.create(user_id: @account.id, isbn: '111')
      BookmoochImport.create(user_id: @account.id, isbn: '222')
      BookmoochImport.clear_imports(@account.id)
      assert_equal 0, BookmoochImport.where(user_id: @account.id).count
    end

    it 'does not delete imports for other users' do
      other = Account.create(email: "other2_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
      BookmoochImport.create(user_id: @account.id, isbn: '111')
      BookmoochImport.create(user_id: other.id, isbn: '222')
      BookmoochImport.clear_imports(@account.id)
      assert_equal 0, BookmoochImport.where(user_id: @account.id).count
      assert_equal 1, BookmoochImport.where(user_id: other.id).count
    end
  end
end
