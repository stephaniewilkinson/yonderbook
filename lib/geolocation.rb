# frozen_string_literal: true

# Turns browser coordinates into a US zip code, and checks that a typed zip is
# real. The single place in this app that touches the `area` gem.
#
# The library lookup is driven by zip: OverDrive's find-libraries-by-query
# endpoint returns an empty list when handed "lat,lon", and area's own to_zip
# only matches coordinates it already has exactly. So a position has to be
# resolved to the nearest zip before it is any use.
#
# `area` is required lazily, not at boot. Loading it reads 43,204 rows into
# ~302k String objects and costs +26.9MB of resident memory, about a quarter of
# this app's startup RSS on a 512MB instance that OOM-kills daily. The bot
# traffic that drives that pressure only ever hits '/', and most sessions never
# reach the library step, so a process that never needs zip data no longer pays
# for it. See #1334 -- replacing the dataset outright is the fuller fix, and
# keeping every use behind this module is what makes that a small change.
module Geolocation
  # Rough miles per degree of latitude. Longitude is scaled by cos(latitude),
  # which is close enough to pick a nearest neighbour and avoids running
  # haversine over 43k rows on a small box.
  MILES_PER_DEGREE = 69.0

  # Beyond this, assume the caller is not in the United States rather than
  # confidently returning a zip hundreds of miles away.
  MAX_DISTANCE_MILES = 100

  # Indexes into area's zipcodes.csv rows.
  ZIP = 0
  CITY = 1
  STATE = 2
  LATITUDE = 3
  LONGITUDE = 4

  module_function

  # True when the string is a zip code that actually exists. Replaces a bare
  # `zip.to_latlon` truthiness check; the coordinates were always discarded.
  def known_zip? zip
    return false unless zip.to_s.match?(/\A\d{5}\z/)

    !zip_codes.assoc(zip).nil?
  end

  # Deferred on purpose -- see the note above the module.
  def zip_codes
    require 'area'
    Area.zip_codes
  end

  # Returns {zip:, city:, state:, distance:} for the closest zip code, or nil
  # when the coordinates are unusable or nowhere near the US.
  def nearest_zip latitude, longitude
    lat = Float(latitude, exception: false)
    lon = Float(longitude, exception: false)
    return unless valid_coordinates? lat, lon

    row, degrees = closest_row lat, lon
    return unless row

    miles = degrees * MILES_PER_DEGREE
    return if miles > MAX_DISTANCE_MILES

    {zip: row[ZIP], city: row[CITY], state: row[STATE], distance: miles.round(1)}
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

    zip_codes.each do |row|
      row_lat = row[LATITUDE].to_f
      row_lon = row[LONGITUDE].to_f
      delta_lat = lat - row_lat
      delta_lon = (lon - row_lon) * scale
      squared = (delta_lat * delta_lat) + (delta_lon * delta_lon)
      next if best_squared && squared >= best_squared

      best = row
      best_squared = squared
    end

    [best, best_squared ? Math.sqrt(best_squared) : nil]
  end
end
