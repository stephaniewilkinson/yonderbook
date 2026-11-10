# frozen_string_literal: true

require 'json'
require_relative 'library_additions'

# Availability alerts (#1422): email a reader when a book on their list that
# their library owns, but had no copy free, comes free.
#
# Turning alerts on stores every copy the reader was just shown, with its
# OverDrive product id. The daily check asks OverDrive only for availability
# of those ids, never searching by title, which is what makes a daily check
# affordable: 25 products a request instead of one request per book.
module AvailabilityAlerts
  module_function

  # Turns alerts on for an account from the results it was just shown, or
  # replaces what it was watching. `titles` are Overdrive::Title copies, whose
  # `library` is the library's name; `libraries` is [[consortium_id, name], ...]
  # as checked. Copies a library owns are watched; books on the list that no
  # library had (`books`, the shelf as searched) are kept for the weekly
  # search instead. Returns the number of copies watched.
  def subscribe user_id, titles:, libraries:, books: [], shelf_name: nil
    rows = watch_rows user_id, titles, libraries
    wanted = LibraryAdditions.wanted_rows user_id, books, titles
    DB.transaction do
      attributes = {
        libraries: JSON.generate(libraries),
        shelf_name: shelf_name,
        enabled: true,
        updated_at: Time.now,
        # The results being saved are a search, just now.
        last_searched_at: Time.now
      }
      if (subscription = AlertSubscription.for_user user_id)
        subscription.update attributes
      else
        AlertSubscription.create attributes.merge(user_id: user_id, unsubscribe_token: AlertSubscription.new_token)
      end
      WatchedTitle.where(user_id: user_id).delete
      WatchedTitle.dataset.multi_insert rows unless rows.empty?
      WantedBook.where(user_id: user_id).delete
      WantedBook.dataset.multi_insert wanted unless wanted.empty?
    end
    rows.length
  end

  def watch_rows user_id, titles, libraries
    ids_by_name = libraries.to_h { |id, name| [name, id.to_s] }
    rows = titles.filter_map do |copy|
      consortium_id = ids_by_name[copy.library]
      next unless consortium_id && copy.id && copy.copies_owned.to_i.positive?

      {
        user_id: user_id,
        consortium_id: consortium_id,
        reserve_id: copy.id.downcase,
        title: copy.title,
        author: copy.author,
        format: copy.format,
        library_name: copy.library,
        url: copy.url,
        copies_available: copy.copies_available.to_i,
        copies_owned: copy.copies_owned.to_i
      }
    end
    rows.uniq { |row| row.values_at(:consortium_id, :reserve_id) }
  end

  # Turning alerts off deletes what they stored rather than flagging it: there
  # is no reason to keep someone's reading list once they've said stop.
  def unsubscribe user_id
    DB.transaction do
      AlertSubscription.where(user_id: user_id).delete
      WatchedTitle.where(user_id: user_id).delete
      WantedBook.where(user_id: user_id).delete
    end
  end

  # The subscription it removed, or nil for a token that matches none.
  def unsubscribe_by_token token
    AlertSubscription.first(unsubscribe_token: token.to_s)&.tap { |subscription| unsubscribe subscription.user_id }
  end

  # Checks every subscription that is due. One reader's failure must not stop
  # the rest, so each is rescued and reported on its own. Returns how many
  # copies readers were emailed about.
  def run_due now: Time.now,
              availability: method(:overdrive_availability),
              deliver: method(:deliver),
              search: LibraryAdditions.method(:overdrive_search)
    AlertSubscription.due(now: now).all.sum do |subscription|
      check(subscription, now: now, availability: availability, deliver: deliver, search: search)
    rescue StandardError => e
      Sentry.capture_exception e
      0
    end
  end

  # Re-checks one subscription and emails it about copies that came free:
  # watched copies that went from none free to some and, when the weekly
  # search is due, copies of wanted books a library has added that are free
  # now. Returns how many copies the email covered (0 when none was sent).
  #
  # The email goes out before anything is saved: if sending fails, nothing
  # changes and tomorrow's check finds the same copies newly free and tries
  # again, rather than having already recorded them as seen.
  def check subscription,
            now: Time.now,
            availability: method(:overdrive_availability),
            deliver: method(:deliver),
            search: LibraryAdditions.method(:overdrive_search)
    updates, newly_free = refreshed_copies subscription, availability
    searched = LibraryAdditions.due? subscription, now
    additions, found_wanted = searched ? LibraryAdditions.find(subscription, search) : [[], []]
    announce = newly_free + additions.select { |row| row.copies_available.positive? }
    sent = announce.any? && deliver.call(subscription, announce)

    DB.transaction do
      updates.each { |row, counts| row.update counts.merge(last_checked_at: now) }
      WatchedTitle.where(id: newly_free.map(&:id)).update(notified_at: now) if sent
      LibraryAdditions.save additions, now: now, notified: sent
      WantedBook.where(id: found_wanted).delete
      subscription.update(
        {last_checked_at: now}.merge(sent ? {last_emailed_at: now} : {}).merge(searched ? {last_searched_at: now} : {})
      )
    end
    sent ? announce.length : 0
  end

  # [[row, {copies_available:, copies_owned:}], ...] for every copy OverDrive
  # answered for, and the rows that went from none free to some. A library
  # that fails is skipped for today (its copies keep their last known counts);
  # a copy OverDrive no longer lists is left alone too.
  def refreshed_copies subscription, availability
    updates = []
    newly_free = []
    WatchedTitle.where(user_id: subscription.user_id).all.group_by(&:consortium_id).each do |consortium_id, rows|
      found = availability.call(consortium_id, rows.map(&:reserve_id))
      rows.each do |row|
        counts = found[row.reserve_id] or next

        newly_free << row if row.copies_available.zero? && counts[:available].positive?
        updates << [row, {copies_available: counts[:available], copies_owned: counts[:owned]}]
      end
    rescue StandardError => e
      Sentry.capture_exception e
    end
    [updates, newly_free]
  end

  def overdrive_availability consortium_id, reserve_ids
    Overdrive.new([], consortium_id).availability_for reserve_ids
  end

  # Only to an open (verified) account. Returns the address once Resend has
  # accepted the email, or nil when there is no one to send to.
  def deliver subscription, copies
    email = DB[:accounts].where(id: subscription.user_id, status_id: 2).get(:email) or return
    unsubscribe_url = "#{base_url}/alerts/unsubscribe/#{subscription.unsubscribe_token}"
    EmailService.send_email(
      to: email,
      subject: subject_for(copies),
      html: EmailTemplates.availability_alert_body(books_from(copies), unsubscribe_url: unsubscribe_url),
      tags: [{name: 'category', value: 'availability_alert'}],
      headers: {'List-Unsubscribe' => "<#{unsubscribe_url}>", 'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click'}
    )
    email
  end

  # The copies grouped into books, in the order the reader will read them:
  # [{title:, author:, copies: [{format:, library_name:, url:}, ...]}, ...]
  def books_from copies
    copies.group_by { |copy| [copy.title, copy.author] }.map do |(title, author), group|
      {title: title, author: author, copies: group.map { |copy| {format: Overdrive.format_label(copy.format), library_name: copy.library_name, url: copy.url} }}
    end
  end

  def subject_for copies
    books = books_from copies
    return "#{books.first[:title]} is available now at #{books.first[:copies].first[:library_name]}" if books.one?

    "#{books.length} books on your list are available now"
  end

  def base_url = ENV.fetch('BASE_URL', 'https://yonderbook.com').chomp('/')
end
