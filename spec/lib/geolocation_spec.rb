# frozen_string_literal: true

require_relative 'spec_helper'
require 'geolocation'

describe Geolocation do
  describe '.known_zip?' do
    it 'accepts a real zip code' do
      assert Geolocation.known_zip?('90210')
    end

    it 'rejects a five-digit number that is not a zip code' do
      refute Geolocation.known_zip?('00001')
    end

    it 'rejects anything that is not five digits' do
      refute Geolocation.known_zip?('9021')
    end

    it 'rejects letters without consulting the dataset' do
      refute Geolocation.known_zip?('ABCDE')
    end

    it 'rejects nil' do
      refute Geolocation.known_zip?(nil)
    end
  end

  describe '.nearest_zip' do
    it 'resolves coordinates in Beverly Hills to a local zip' do
      found = Geolocation.nearest_zip 34.0901, -118.4065

      assert_equal 'CA', found[:state]
      assert_equal 'Beverly Hills', found[:city]
    end

    it 'resolves coordinates in Manhattan to a New York zip' do
      found = Geolocation.nearest_zip 40.7484, -73.9857

      assert_equal 'NY', found[:state]
    end

    it 'reports how far the match is, so callers can judge it' do
      found = Geolocation.nearest_zip 34.0901, -118.4065

      assert_operator found[:distance], :<, 5
    end

    it 'accepts coordinates as strings, as they arrive from a query string' do
      found = Geolocation.nearest_zip '34.0901', '-118.4065'

      assert_equal 'CA', found[:state]
    end

    # Someone in London must not be told they live in Maine.
    it 'returns nothing when the caller is nowhere near the United States' do
      assert_nil Geolocation.nearest_zip(51.5074, -0.1278)
    end

    it 'returns nothing for coordinates in the middle of the Pacific' do
      assert_nil Geolocation.nearest_zip(0, -160)
    end

    it 'returns nothing for unparseable input' do
      assert_nil Geolocation.nearest_zip('not', 'coordinates')
    end

    it 'returns nothing for nil' do
      assert_nil Geolocation.nearest_zip(nil, nil)
    end

    it 'returns nothing for out-of-range latitude' do
      assert_nil Geolocation.nearest_zip(200, -118)
    end

    it 'returns nothing for out-of-range longitude' do
      assert_nil Geolocation.nearest_zip(34, 999)
    end

    it 'returns a zip the library lookup can actually use' do
      found = Geolocation.nearest_zip 34.0901, -118.4065

      assert_match(/\A\d{5}\z/, found[:zip])
    end
  end
end
