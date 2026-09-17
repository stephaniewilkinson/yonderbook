# frozen_string_literal: true

require_relative 'spec_helper'

describe TupleSpace do
  before do
    @space = TupleSpace.new reaper_period_in_secs: 0.1, expires_in_secs: 0.1
  end

  it 'gets and sets' do
    assert_equal @space[:wombat] = 'wombat', 'wombat'
    assert_equal @space[:wombat], 'wombat'
  end

  it 'deletes' do
    @space[:poof] = 'poof'
    assert_equal @space.delete(:poof), 'poof'
    assert_nil @space[:poof]
  end

  it 'expires old entries' do
    @space[:old] = 'old'
    sleep 0.3
    assert_nil @space[:old]
  end

  describe '#store' do
    # `[]=` cannot take a third argument, so anything wanting a lifetime other
    # than the default goes through store. Cache uses it to expire an abandoned
    # anonymous session sooner than a signed-in one.
    it 'defaults to the space-wide expiry' do
      space = TupleSpace.new expires_in_secs: 60

      space.store 'k', 'v'

      assert_equal 'v', space['k']
    end

    it 'accepts a shorter lifetime for one entry' do
      space = TupleSpace.new expires_in_secs: 60

      space.store 'short', 'v', expires_in_secs: 0.05
      space.store 'long', 'v'

      sleep 0.2

      assert_nil space['short']
      assert_equal 'v', space['long']
    end

    it 'replaces a value rather than accumulating tuples' do
      space = TupleSpace.new expires_in_secs: 60

      space.store 'k', 'first'
      space.store 'k', 'second'

      assert_equal 'second', space['k']
      assert_nil(space.delete('k').then { space['k'] })
    end

    it 'exposes its default so callers can fall back to it' do
      assert_equal 60, TupleSpace.new(expires_in_secs: 60).expires_in_secs
    end
  end
end
