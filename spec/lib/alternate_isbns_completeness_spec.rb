# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'

# Run migrations before loading models (model introspects table at load time)
Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

require 'alternate_isbns'
require 'models/isbn_alternate'

COMPLETENESS_ISBNS = %w[9780140328721 9780140328722 9780140328723 9780140328724 9780140328725 9780140328726].freeze

# The lookup has to actually suspend for this to reproduce anything: a stub that
# returns without yielding leaves no task in flight for `barrier.wait` to return
# early on. Two seconds against a 1.4/sec limiter keeps several outstanding at
# the moment the last one is admitted.
SLOW_LOOKUP = ->(isbn) {
  sleep 2
  [["alt-#{isbn}"], "work-#{isbn}"]
}

# Only the semaphore tasks are registered with the barrier, and a semaphore task
# used to finish as soon as it had *scheduled* its limiter child. So
# `barrier.wait` returned on work still in flight: against Open Library it came
# back with 19 of 21 books filled in and the rest arrived seconds later, into a
# hash the caller had already read.
#
# Standalone that is invisible -- `Sync` outside a reactor runs one to
# completion, so the children finish before the method returns. It only shows
# under Falcon, where we are already in a reactor and `Sync` runs inline. Hence
# the `Async` wrapper here: without it this passes on the broken code.
describe 'AlternateIsbns completeness' do
  before do
    DB[:isbn_alternates].delete
  end

  # Both snapshots are taken inside the reactor, at the instant the method
  # returns, because that is when its caller reads them -- Bookmooch hands the
  # hash straight to expand_isbns_with_alternates. Reading after the reactor has
  # drained would show the orphans' late writes and pass either way.
  it 'returns every requested ISBN when called from inside a reactor' do
    observed = nil
    AlternateIsbns.stub(:fetch_alternates_for_isbn_with_retry, SLOW_LOOKUP) do
      Async { observed = AlternateIsbns.fetch_alternate_isbns(COMPLETENESS_ISBNS).keys.sort }.wait
    end

    assert_equal COMPLETENESS_ISBNS.sort, observed
  end

  it 'reports progress for every ISBN before it returns' do
    reported = []
    collect = ->(update) { reported << update[:current] if update[:type] == 'progress' }

    furthest = nil
    AlternateIsbns.stub(:fetch_alternates_for_isbn_with_retry, SLOW_LOOKUP) do
      task = Async do
        AlternateIsbns.fetch_alternate_isbns(COMPLETENESS_ISBNS, &collect)
        furthest = reported.max
      end
      task.wait
    end

    # Late progress messages are what overwrote "Sending N ISBNs to BookMooch..."
    # on the import page with a stale "Fetching alternate ISBNs" line.
    assert_equal COMPLETENESS_ISBNS.size, furthest, 'progress stopped short of the last ISBN'
  end
end
