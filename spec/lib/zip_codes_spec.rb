# frozen_string_literal: true

require_relative 'spec_helper'
require 'zip_codes'

describe ZipCodes do
  describe '.known?' do
    it 'recognises a real zip code' do
      assert ZipCodes.known?('90210')
    end

    it 'recognises the first row, which a binary search can miss' do
      assert ZipCodes.known?('00210')
    end

    it 'rejects a five-digit number that is not a zip code' do
      refute ZipCodes.known?('00001')
    end

    it 'rejects the wrong length' do
      refute ZipCodes.known?('9021')
    end

    # Cheap guard first, so junk never triggers the dataset load at all.
    it 'rejects letters' do
      refute ZipCodes.known?('ABCDE')
    end

    it 'rejects nil' do
      refute ZipCodes.known?(nil)
    end
  end

  describe '.index_of' do
    it 'finds a row in the middle of the table' do
      middle = ZipCodes.count / 2

      assert_equal middle, ZipCodes.index_of(ZipCodes.row(middle)[:zip])
    end

    it 'finds the very last row' do
      last = ZipCodes.row(ZipCodes.count - 1)

      assert_equal ZipCodes.count - 1, ZipCodes.index_of(last[:zip])
    end

    it 'returns nothing for an absent zip' do
      assert_nil ZipCodes.index_of('00001')
    end
  end

  describe '.row' do
    it 'returns the place for an index' do
      found = ZipCodes.row ZipCodes.index_of('90210')

      assert_equal({zip: '90210', city: 'Beverly Hills', state: 'CA'}, found)
    end

    it 'returns nothing past the end of the table' do
      assert_nil ZipCodes.row(ZipCodes.count)
    end

    it 'returns nothing for a negative index' do
      assert_nil ZipCodes.row(-1)
    end
  end

  describe '.coordinates' do
    it 'returns latitude and longitude for a zip' do
      lat, lon = ZipCodes.coordinates '90210'

      assert_in_delta 34.0888, lat, 0.01
      assert_in_delta(-118.4061, lon, 0.01)
    end

    it 'returns nothing for an absent zip' do
      assert_nil ZipCodes.coordinates('00001')
    end
  end

  describe '.each_coordinate' do
    it 'yields every row' do
      yielded = 0
      ZipCodes.each_coordinate { |_index, _lat, _lon| yielded += 1 }

      assert_equal ZipCodes.count, yielded
    end

    it 'yields usable coordinates' do
      seen = nil
      ZipCodes.each_coordinate { |_index, lat, lon| seen = [lat, lon] }

      assert_kind_of Float, seen.first
      assert_kind_of Float, seen.last
    end
  end

  describe 'the table itself' do
    it 'holds the whole country' do
      assert_operator ZipCodes.count, :>, 40_000
    end

    # The binary search depends on this and would silently return wrong
    # answers if the data file were ever regenerated unsorted.
    it 'is sorted by zip, which the binary search relies on' do
      sample = (0...ZipCodes.count).step(500).map { |i| ZipCodes.row(i)[:zip] }

      assert_equal sample.sort, sample
    end
  end
end
