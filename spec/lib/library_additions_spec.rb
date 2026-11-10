# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'

Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

require 'availability_alerts'
require 'email'
require 'email_templates'
require 'models/account'
require 'models/alert_subscription'
require 'models/wanted_book'
require 'models/watched_title'
require 'overdrive'
require 'sentry-ruby'

# #1422, part 2: books none of the reader's libraries had, searched for weekly
# and announced when a library adds them with a copy free.
describe LibraryAdditions do
  before do
    DB.run('PRAGMA foreign_keys = OFF')
    DB.tables.each { |t| DB[t].delete }
    DB.run('PRAGMA foreign_keys = ON')
    @account = Account.create(email: "reader_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
    @sent = []
  end

  def copy title, id:, library: 'Seattle', available: 0, owned: 2
    Overdrive::Title.new(
      title: title,
      author: 'Ann Author',
      image: nil,
      copies_available: available,
      copies_owned: owned,
      isbn: nil,
      url: "https://seattle.overdrive.com/media/#{id}",
      id: id,
      format: 'ebook-overdrive',
      library: library,
      no_isbn: false,
      date_added: nil
    )
  end

  def shelf *titles
    titles.map { |title| {title: title, author: 'Ann Author', isbn: nil} }
  end

  def searched_copy title, id:, available:
    copy(title, id: id, available: available, library: nil)
  end

  # Subscribed with nothing owned, and the weekly search due.
  def wanting *titles
    AvailabilityAlerts.subscribe @account.id, titles: [], libraries: [%w[1135 Seattle]], books: shelf(*titles)
    AlertSubscription.for_user(@account.id).tap { |subscription| subscription.update last_searched_at: Time.now - (8 * 86_400) }
  end

  def check_with_search subscription, found, deliver: ->(_subscription, copies) { (@sent << copies.map(&:title)).last }
    @searched = []
    search = ->(consortium, books) do
      @searched << [consortium, books.map { |book| book[:title] }.sort]
      found
    end
    AvailabilityAlerts.check subscription, availability: ->(*) { {} }, deliver: deliver, search: search
  end

  it 'keeps the books no library had when alerts are turned on' do
    AvailabilityAlerts.subscribe @account.id, titles: [copy('Owned', id: 'AAA')], libraries: [%w[1135 Seattle], %w[1047 NYPL]], books: shelf('Owned', 'Missing')

    assert_equal %w[Missing], WantedBook.where(user_id: @account.id).map(&:title)
  end

  it 'emails about a wanted book a library added with a copy free, and starts watching it' do
    subscription = wanting 'Piranesi', 'Still missing'

    assert_equal 1, check_with_search(subscription, [searched_copy('Piranesi', id: 'NEW', available: 1)])
    assert_equal [['1135', ['Piranesi', 'Still missing']]], @searched
    assert_equal [%w[Piranesi]], @sent
    assert_equal %w[new], WatchedTitle.where(user_id: @account.id).map(&:reserve_id)
    assert_equal ['Still missing'], WantedBook.where(user_id: @account.id).map(&:title)
    refute_nil subscription.reload.last_searched_at
  end

  it 'watches an added book with no copy free, without emailing yet' do
    subscription = wanting 'Piranesi'

    assert_equal 0, check_with_search(subscription, [searched_copy('Piranesi', id: 'NEW', available: 0)])
    assert_empty @sent
    assert_equal 1, WatchedTitle.where(user_id: @account.id).count
    assert_equal 0, WantedBook.where(user_id: @account.id).count
  end

  it 'searches no more than once a week' do
    subscription = wanting 'Piranesi'
    subscription.update last_searched_at: Time.now - 86_400

    check_with_search subscription, [searched_copy('Piranesi', id: 'NEW', available: 1)]

    assert_empty @searched
  end

  it 'keeps wanting a book when the email about it fails, so it is found again' do
    subscription = wanting 'Piranesi'

    assert_raises(RuntimeError) do
      check_with_search subscription, [searched_copy('Piranesi', id: 'NEW', available: 1)], deliver: ->(*) { raise 'Resend is down' }
    end
    assert_equal 1, WantedBook.where(user_id: @account.id).count
    assert_equal 0, WatchedTitle.where(user_id: @account.id).count
  end

  it 'keeps wanting a book when the library search fails' do
    subscription = wanting 'Piranesi'
    AvailabilityAlerts.check subscription, availability: ->(*) { {} }, deliver: ->(*) { 'sent' }, search: ->(*) { raise 'OverDrive 503' }

    assert_equal 1, WantedBook.where(user_id: @account.id).count
  end

  it 'is deleted when alerts are turned off' do
    wanting 'Piranesi'
    AvailabilityAlerts.unsubscribe @account.id

    assert_equal 0, WantedBook.where(user_id: @account.id).count
  end
end
