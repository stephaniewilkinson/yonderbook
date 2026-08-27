# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Goodreads CSV import' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour

  let :app do
    App
  end

  def fixture name
    File.expand_path "../fixtures/#{name}", __dir__
  end

  # An account with no Goodreads connection at all -- the whole point of the
  # import path is that it works without one.
  def logged_in_account
    email, password = create_account_direct
    password_login email, password
    DB[:accounts].where(email: email).first
  end

  def import fixture_name
    visit '/import'
    attach_file 'library', fixture(fixture_name)
    click_button 'Import my library'
  end

  it 'requires a login' do
    visit '/import'

    refute_text 'How to get your export'
  end

  it 'stores the library and sends the user to their shelves' do
    logged_in_account
    import 'goodreads_export.csv'

    assert_text 'Imported 3 books'
    assert_text 'Choose a shelf'
  end

  it 'builds shelves from both the exclusive shelf and the named bookshelves' do
    logged_in_account
    import 'goodreads_export.csv'

    assert_text 'to-read'
    assert_text 'sci-fi'
  end

  it 'persists the library to the database rather than the session' do
    account = logged_in_account
    import 'goodreads_export.csv'

    assert_equal 3, DB[:imported_books].where(user_id: account[:id]).count
  end

  it 'treats an unrated book as rating 0 rather than dropping it' do
    account = logged_in_account
    import 'goodreads_export.csv'
    hunger_games = DB[:imported_books].where(user_id: account[:id], goodreads_book_id: '2767052').first

    assert_equal 0, hunger_games[:rating]
  end

  it 'normalizes Date Added to a sortable ISO date' do
    account = logged_in_account
    import 'goodreads_export.csv'
    sower = DB[:imported_books].where(user_id: account[:id], goodreads_book_id: '25489134').first

    assert_equal '2019-11-02', sower[:date_added]
  end

  it 'opens an imported shelf without a Goodreads connection' do
    logged_in_account
    import 'goodreads_export.csv'
    visit '/goodreads/shelves/to-read'

    assert_text 'Your to-read shelf'
  end

  it 'rejects a CSV that is not a Goodreads export, with an actionable message' do
    logged_in_account
    import 'not_goodreads.csv'

    assert_text 'goodreads.com/review/import'
  end

  it 'keeps the user on the import page when the upload is rejected' do
    logged_in_account
    import 'not_goodreads.csv'

    assert_text 'How to get your export'
  end

  it 'replaces the previous import rather than merging into it' do
    account = logged_in_account
    import 'goodreads_export.csv'
    import 'goodreads_export.csv'

    assert_equal 3, DB[:imported_books].where(user_id: account[:id]).count
  end

  it 'removes the imported library on request' do
    account = logged_in_account
    import 'goodreads_export.csv'
    visit '/import'
    accept_confirm { click_button 'Remove it' }

    assert_equal 0, DB[:imported_books].where(user_id: account[:id]).count
  end

  it 'offers the import path from the Goodreads connect page' do
    logged_in_account
    visit '/goodreads'

    assert_link 'Import a CSV export instead'
  end
end
