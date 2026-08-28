# frozen_string_literal: true

namespace :zipcodes do
  desc 'Rebuild data/zipcodes.csv from a source table (zip,city,state,lat,lon,...)'
  task :build, [:source] do |_t, args|
    require 'csv'
    source = args[:source] or raise 'Usage: rake zipcodes:build[/path/to/zipcodes.csv]'

    seen = {}
    CSV.foreach(source) do |zip, city, state, lat, lon, *|
      next unless zip.to_s.match?(/\A\d{5}\z/)
      next if lat.to_s.empty? || lon.to_s.empty?

      seen[zip] ||= [zip, lat.to_f, lon.to_f, city.to_s.strip, state.to_s.strip]
    end

    rows = seen.values.sort_by(&:first)
    File.open('data/zipcodes.csv', 'w') do |file|
      file.puts '# US zip codes with centroid coordinates: zip,latitude,longitude,city,state'
      file.puts '# Sorted by zip so lookups can binary search a fixed-width index.'
      file.puts '# Derived from the area gem (MIT, Copyright 2012 Jonathan Vingiano),'
      file.puts '# trimmed to the five columns this app uses. Regenerate with:'
      file.puts '#   bundle exec rake zipcodes:build[/path/to/zipcodes.csv]'
      rows.each { |zip, lat, lon, city, state| file.puts "#{zip},#{lat},#{lon},#{city},#{state}" }
    end
    puts "Wrote #{rows.size} rows to data/zipcodes.csv"
  end
end
