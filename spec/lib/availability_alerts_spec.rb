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
require 'models/watched_title'
require 'overdrive'
require 'sentry-ruby'

# #1422. The decisions that matter: what is watched, when a reader is emailed,
# and that a failed email is retried rather than lost.
describe AvailabilityAlerts do
  LIBRARIES = [%w[1135 Seattle], %w[1047 NYPL]].freeze

  before do
    DB.run('PRAGMA foreign_keys = OFF')
    DB.tables.each { |t| DB[t].delete }
    DB.run('PRAGMA foreign_keys = ON')
    @account = Account.create(email: "reader_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
    @sent = []
  end

  def copy title, id:, library: 'Seattle', available: 0, owned: 2, format: 'ebook-overdrive'
    Overdrive::Title.new(
      title: title,
      author: 'Ann Author',
      image: nil,
      copies_available: available,
      copies_owned: owned,
      isbn: nil,
      url: "https://seattle.overdrive.com/media/#{id}",
      id: id,
      format: format,
      library: library,
      no_isbn: false,
      date_added: nil
    )
  end

  def subscribe titles
    AvailabilityAlerts.subscribe @account.id, titles: titles, libraries: LIBRARIES, shelf_name: 'to-read'
    AlertSubscription.for_user @account.id
  end

  # availability: {reserve_id => available} for every library.
  def check subscription, available, now: Time.now
    source = ->(_consortium, ids) { ids.to_h { |id| [id, {available: available.fetch(id, 0), owned: 2}] } }
    deliver = ->(_subscription, copies) { (@sent << copies.map(&:title)).last }
    AvailabilityAlerts.check subscription, now: now, availability: source, deliver: deliver
  end

  describe '.subscribe' do
    it 'watches every copy a library owns, under its consortium id, and nothing it does not own' do
      subscribe [
        copy('Waiting', id: 'AAA'),
        copy('Here now', id: 'BBB', available: 1),
        copy('Not owned', id: 'CCC', owned: 0),
        copy('At NYPL', id: 'DDD', library: 'NYPL')
      ]

      watched = WatchedTitle.where(user_id: @account.id).order(:reserve_id).all
      assert_equal %w[aaa bbb ddd], watched.map(&:reserve_id)
      assert_equal %w[1135 1135 1047], watched.map(&:consortium_id)
    end

    it 'replaces what was watched when turned on again' do
      subscribe [copy('Old', id: 'AAA')]
      subscribe [copy('New', id: 'BBB')]

      assert_equal %w[New], WatchedTitle.where(user_id: @account.id).map(&:title)
      assert_equal 1, AlertSubscription.where(user_id: @account.id).count
    end
  end

  describe '.check' do
    it 'emails when a copy goes from none free to one free' do
      subscription = subscribe [copy('Piranesi', id: 'AAA'), copy('Still waiting', id: 'BBB')]

      assert_equal 1, check(subscription, {'aaa' => 1})
      assert_equal [%w[Piranesi]], @sent
      refute_nil WatchedTitle.first(reserve_id: 'aaa').notified_at
      refute_nil subscription.reload.last_emailed_at
    end

    it 'does not email about a copy that was already free when alerts were turned on' do
      subscription = subscribe [copy('Here now', id: 'AAA', available: 1)]

      assert_equal 0, check(subscription, {'aaa' => 1})
      assert_empty @sent
    end

    it 'emails once per transition, not every day it stays free' do
      subscription = subscribe [copy('Piranesi', id: 'AAA')]
      check subscription, {'aaa' => 1}, now: Time.now - 86_400
      check subscription.reload, {'aaa' => 1}

      assert_equal 1, @sent.length
    end

    it 'emails again when a copy is taken and comes free again' do
      subscription = subscribe [copy('Piranesi', id: 'AAA')]
      check subscription, {'aaa' => 1}
      check subscription.reload, {'aaa' => 0}
      check subscription.reload, {'aaa' => 1}

      assert_equal 2, @sent.length
    end

    # The email goes out before anything is saved, so a failure leaves the
    # copy looking newly free for tomorrow's run.
    it 'changes nothing when the email fails, so tomorrow retries it' do
      subscription = subscribe [copy('Piranesi', id: 'AAA')]
      failing = ->(_subscription, _copies) { raise 'Resend is down' }
      source = ->(_consortium, ids) { ids.to_h { |id| [id, {available: 1, owned: 2}] } }

      assert_raises(RuntimeError) { AvailabilityAlerts.check subscription, availability: source, deliver: failing }
      assert_equal 0, WatchedTitle.first(reserve_id: 'aaa').copies_available
      assert_nil subscription.reload.last_checked_at
    end

    it 'skips a library that fails and still checks the others' do
      subscription = subscribe [copy('Seattle book', id: 'AAA'), copy('NYPL book', id: 'BBB', library: 'NYPL')]
      source = ->(consortium, ids) do
        raise 'OverDrive 503' if consortium == '1135'

        ids.to_h { |id| [id, {available: 1, owned: 2}] }
      end
      deliver = ->(_subscription, copies) { (@sent << copies.map(&:title)).last }

      AvailabilityAlerts.check subscription, availability: source, deliver: deliver

      assert_equal [['NYPL book']], @sent
    end
  end

  describe '.run_due' do
    it 'checks only subscriptions not checked in the last 20 hours' do
      subscription = subscribe [copy('Piranesi', id: 'AAA')]
      subscription.update last_checked_at: Time.now - 3600
      source = ->(_consortium, ids) { ids.to_h { |id| [id, {available: 1, owned: 2}] } }

      assert_equal 0, AvailabilityAlerts.run_due(availability: source, deliver: ->(*) { 'sent' })

      subscription.update last_checked_at: Time.now - (21 * 3600)
      assert_equal 1, AvailabilityAlerts.run_due(availability: source, deliver: ->(*) { 'sent' })
    end
  end

  describe '.unsubscribe_by_token' do
    it 'deletes the subscription and everything it watched' do
      subscription = subscribe [copy('Piranesi', id: 'AAA')]

      refute_nil AvailabilityAlerts.unsubscribe_by_token(subscription.unsubscribe_token)
      assert_nil AlertSubscription.for_user(@account.id)
      assert_equal 0, WatchedTitle.where(user_id: @account.id).count
    end

    it 'does nothing for a token that matches no one' do
      subscribe [copy('Piranesi', id: 'AAA')]

      assert_nil AvailabilityAlerts.unsubscribe_by_token('not-a-token')
      refute_nil AlertSubscription.for_user(@account.id)
    end
  end

  describe 'the email' do
    it 'escapes titles from an uploaded export, and links each copy' do
      rows = [WatchedTitle.new(title: '<script>x</script>', author: 'A & B', format: 'audiobook-overdrive', library_name: 'Seattle', url: 'https://example.org/a')]
      html = EmailTemplates.availability_alert_body(AvailabilityAlerts.books_from(rows), unsubscribe_url: 'https://yonderbook.com/alerts/unsubscribe/t')

      refute_includes html, '<script>x</script>'
      assert_includes html, '&lt;script&gt;'
      assert_includes html, 'A &amp; B'
      assert_includes html, 'href="https://example.org/a"'
      assert_includes html, 'https://yonderbook.com/alerts/unsubscribe/t'
    end

    it 'names the book and library in the subject when there is one' do
      rows = [WatchedTitle.new(title: 'Piranesi', author: 'Susanna Clarke', format: 'ebook-overdrive', library_name: 'Seattle', url: 'u')]

      assert_equal 'Piranesi is available now at Seattle', AvailabilityAlerts.subject_for(rows)
    end

    it 'only goes to an open account' do
      subscription = subscribe [copy('Piranesi', id: 'AAA')]
      @account.update status_id: 1

      assert_nil AvailabilityAlerts.deliver(subscription, WatchedTitle.where(user_id: @account.id).all)
    end
  end
end
