# frozen_string_literal: true

require_relative 'spec_helper'

# #1416. A privacy page, terms, and a way to delete an account and
# everything stored with it.
describe 'privacy, terms and deleting an account' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour

  %w[/privacy /terms].each do |path|
    it "serves #{path}, linked from every page and the sitemap" do
      visit path
      assert_text 'Last updated'

      visit '/'
      assert_selector "footer a[href='#{path}']"

      visit '/sitemap.xml'
      assert_includes page.html, "https://yonderbook.com#{path}</loc>"
    end
  end

  it 'points to both from the sign-up page' do
    visit '/sign-up'

    assert_selector "main a[href='/terms']", text: 'Terms'
    assert_selector "main a[href='/privacy']", text: 'Privacy'
  end

  # Every table that holds something about an account. The first three cascade;
  # the Rodauth key tables are cleared by after_close_account, or foreign keys
  # would refuse the delete.
  def rows_for id
    {
      accounts: DB[:accounts].where(id:).count,
      goodreads_connections: DB[:goodreads_connections].where(user_id: id).count,
      imported_books: DB[:imported_books].where(user_id: id).count,
      bookmooch_imports: DB[:bookmooch_imports].where(user_id: id).count,
      account_password_reset_keys: DB[:account_password_reset_keys].where(id:).count,
      alert_subscriptions: DB[:alert_subscriptions].where(user_id: id).count,
      watched_titles: DB[:watched_titles].where(user_id: id).count
    }
  end

  it 'deletes the account and everything stored with it' do
    email, password = create_account_direct
    id = DB[:accounts].where(email:).get(:id)
    add_goodreads_connection id, '42', 'token', 'secret'
    DB[:bookmooch_imports].insert(user_id: id, isbn: '9780062316097')
    # A leftover reset link: the row that would block the delete without the hook.
    DB[:account_password_reset_keys].insert(id:, key: 'k', deadline: Time.now + 3600)
    DB[:alert_subscriptions].insert(user_id: id, unsubscribe_token: "t#{id}")
    DB[:watched_titles].insert(user_id: id, consortium_id: '1135', reserve_id: 'r', title: 'T')
    password_login email, password
    visit '/import'
    attach_file 'library', File.expand_path('../fixtures/goodreads_export.csv', __dir__)
    click_button 'import-submit'
    assert_text 'Imported 3 books'
    assert(rows_for(id).values.all?(&:positive?), "expected rows to delete, got #{rows_for(id)}")

    visit '/account'
    click_link 'Delete my account'
    fill_in 'Your password', with: password
    click_button 'close-account-submit'

    assert_current_path '/'
    assert_text 'Your account and everything stored with it have been deleted'
    assert(rows_for(id).values.all?(&:zero?), "rows left behind: #{rows_for(id)}")
  end

  it 'refuses without the password' do
    email, password = create_account_direct
    password_login email, password
    visit '/account'
    click_link 'Delete my account'
    fill_in 'Your password', with: 'not-the-password'
    click_button 'close-account-submit'

    assert_equal 1, DB[:accounts].where(email:).count
  end
end
