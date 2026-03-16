# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'

# Run migrations before loading models (model introspects table at load time)
Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

require 'models/isbn_alternate'

describe IsbnAlternate do
  before do
    DB[:isbn_alternates].delete
  end

  describe '.store and .bulk_lookup' do
    it 'stores and retrieves alternates' do
      IsbnAlternate.store('9780140328721', %w[9780141311234 9780142410387], work_key: 'OL45804W')

      results = IsbnAlternate.bulk_lookup(%w[9780140328721])
      assert_equal %w[9780141311234 9780142410387], results['9780140328721']
    end

    it 'retrieves multiple ISBNs in one query' do
      IsbnAlternate.store('111', %w[222 333])
      IsbnAlternate.store('444', %w[555])
      IsbnAlternate.store('666', [])

      results = IsbnAlternate.bulk_lookup(%w[111 444 666 999])
      assert_equal %w[222 333], results['111']
      assert_equal %w[555], results['444']
      assert_equal [], results['666']
      assert_nil results['999']
    end

    it 'upserts on conflict' do
      IsbnAlternate.store('111', %w[222])
      IsbnAlternate.store('111', %w[333 444])

      results = IsbnAlternate.bulk_lookup(%w[111])
      assert_equal %w[333 444], results['111']
    end

    it 'excludes stale entries' do
      IsbnAlternate.store('111', %w[222])
      DB[:isbn_alternates].where(isbn: '111').update(created_at: Time.now - (31 * 86_400))

      results = IsbnAlternate.bulk_lookup(%w[111])
      assert_nil results['111']
    end

    it 'includes entries within TTL' do
      IsbnAlternate.store('111', %w[222])
      DB[:isbn_alternates].where(isbn: '111').update(created_at: Time.now - (29 * 86_400))

      results = IsbnAlternate.bulk_lookup(%w[111])
      assert_equal %w[222], results['111']
    end
  end
end
