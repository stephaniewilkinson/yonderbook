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
end
