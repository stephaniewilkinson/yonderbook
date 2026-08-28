# frozen_string_literal: true

require_relative 'zip_codes'

# Turns browser coordinates into a US zip code, and checks that a typed zip is
# real.
#
# The library lookup is driven by zip: OverDrive's find-libraries-by-query
# endpoint returns an empty list when handed "lat,lon", and area's own to_zip
# only matches coordinates it already has exactly. So a position has to be
# resolved to the nearest zip before it is any use.
#
# The zip table itself lives in ZipCodes, which loads lazily and holds packed
# blobs rather than per-row objects. See #1334.
module Geolocation
  # Rough miles per degree of latitude. Longitude is scaled by cos(latitude),
  # which is close enough to pick a nearest neighbour and avoids running
  # haversine over 43k rows on a small box.
  MILES_PER_DEGREE = 69.0

  # Beyond this, assume the caller is not in the United States rather than
  # confidently returning a zip hundreds of miles away.
  MAX_DISTANCE_MILES = 100

  module_function

  # True when the string is a zip code that actually exists. Replaces a bare
  # `zip.to_latlon` truthiness check; the coordinates were always discarded.
  def known_zip?(zip) = ZipCodes.known?(zip)

  # Returns {zip:, city:, state:, distance:} for the closest zip code, or nil
  # when the coordinates are unusable or nowhere near the US.
  def nearest_zip latitude, longitude
    lat = Float(latitude, exception: false)
    lon = Float(longitude, exception: false)
    return unless valid_coordinates? lat, lon

    index, degrees = closest_row lat, lon
    return unless index

    miles = degrees * MILES_PER_DEGREE
    return if miles > MAX_DISTANCE_MILES

    ZipCodes.row(index).merge distance: miles.round(1)
  end

  def valid_coordinates? lat, lon
    return false unless lat && lon

    lat.between?(-90, 90) && lon.between?(-180, 180)
  end

  # Squared distance in degrees, longitude corrected for latitude. Comparing
  # squares avoids a square root per row; only the winner is converted.
  def closest_row lat, lon
    scale = Math.cos(lat * Math::PI / 180)
    best = nil
    best_squared = nil

    ZipCodes.each_coordinate do |index, row_lat, row_lon|
      delta_lat = lat - row_lat
      delta_lon = (lon - row_lon) * scale
      squared = (delta_lat * delta_lat) + (delta_lon * delta_lon)
      next if best_squared && squared >= best_squared

      best = index
      best_squared = squared
    end

    [best, best_squared ? Math.sqrt(best_squared) : nil]
  end
end
