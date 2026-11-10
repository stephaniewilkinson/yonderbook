# frozen_string_literal: true

require_relative 'spec_helper'
require 'tempfile'

# #1414. A visitor without an account can upload a Goodreads CSV export and
# use it straight away. It is held in the session cache only, and kept if
# they sign up.
describe 'importing a library without an account' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour

  def fixture name
    File.expand_path "../fixtures/#{name}", __dir__
  end

  def upload path
    visit '/import'
    attach_file 'library', path
    click_button 'import-submit'
  end

  it 'lists the uploaded shelves without an account' do
    upload fixture('goodreads_export.csv')

    assert_current_path '/search/shelves'
    assert_text 'Imported 3 books'
    assert_text 'Choose a shelf'
    assert_text 'to-read'
  end

  it 'opens an uploaded shelf without asking Goodreads for anything' do
    upload fixture('goodreads_export.csv')
    visit '/search/shelves/to-read'

    assert_text 'Publication Years'
  end

  it 'writes nothing to the database for a visitor without an account' do
    before = DB[:imported_books].count
    upload fixture('goodreads_export.csv')

    assert_text 'Imported 3 books'
    assert_equal before, DB[:imported_books].count
  end

  it 'says the upload lasts for this visit, and offers an account to keep it' do
    upload fixture('goodreads_export.csv')
    visit '/import'

    assert_text 'Kept for this visit only'
    assert_link 'Create a free account'
  end

  it 'can be removed again' do
    upload fixture('goodreads_export.csv')
    visit '/import'
    accept_confirm { click_button 'Remove it' }

    assert_text 'Your imported library has been removed'
    visit '/search/shelves'
    assert_current_path '/'
  end

  it 'turns away more books than a visitor without an account can hold' do
    csv = Tempfile.new(['export', '.csv'])
    lines = File.readlines(fixture('goodreads_export.csv'))
    csv.write lines.first
    (ImportRoutes::ANONYMOUS_MAX_BOOKS + 1).times { |i| csv.write lines[1].sub(/\A\d+/, (i + 900_000).to_s) }
    csv.close

    upload csv.path

    assert_current_path '/import'
    assert_text 'Create a free account to import up to'
  ensure
    csv&.unlink
  end

  it 'keeps the upload when the visitor signs up' do
    upload fixture('goodreads_export.csv')
    email = "test_anon_import_#{SecureRandom.hex(6)}@example.com"
    visit '/sign-up'
    fill_in 'Email', with: email
    fill_in 'Password', with: 'SecurePassword123!'
    click_button 'Create Account'
    assert_text 'Check Your Email'

    account = DB[:accounts].where(email: email).first
    assert_equal 3, DB[:imported_books].where(user_id: account[:id]).count
  end
end
