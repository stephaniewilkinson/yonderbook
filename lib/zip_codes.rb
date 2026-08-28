# frozen_string_literal: true

# The US zip code table, in about a megabyte instead of twenty-seven.
#
# This replaces the `area` gem, which read 43,204 rows into ~302k Ruby String
# objects and cost +26.9MB resident -- roughly a quarter of this app's startup
# RSS on a 512MB instance that OOM-kills daily. See #1334.
#
# Everything is held as packed blobs rather than per-row objects:
#
#   zips    one frozen String, five bytes per row, sorted so a lookup can
#           binary search it without an index
#   lats    Array of Float; on 64-bit these are immediates, so the array is
#           pointers only and scanning it needs no allocation
#   lons    likewise
#   places  one frozen String of "City,ST" with an offset table, sliced only
#           for the single row a lookup actually returns
#
# Loaded lazily. A process that never serves the library flow never pays for it.
module ZipCodes
  PATH = File.expand_path '../data/zipcodes.csv', __dir__
  ZIP_WIDTH = 5

  class << self
    def known? zip
      return false unless zip.to_s.match?(/\A\d{5}\z/)

      !index_of(zip).nil?
    end

    def count
      load_data
      @count
    end

    # [latitude, longitude] for a zip, or nil.
    def coordinates zip
      index = index_of zip
      return unless index

      [@lats[index], @lons[index]]
    end

    # {zip:, city:, state:} for a row index.
    def row index
      load_data
      return unless index && index >= 0 && index < @count

      city, state = place(index).split ','
      {zip: @zips.byteslice(index * ZIP_WIDTH, ZIP_WIDTH), city: city, state: state}
    end

    # Yields [index, latitude, longitude] for every row.
    def each_coordinate
      load_data
      @count.times { |i| yield i, @lats[i], @lons[i] }
    end

    def index_of zip
      load_data
      low = 0
      high = @count - 1
      while low <= high
        middle = (low + high) / 2
        case @zips.byteslice(middle * ZIP_WIDTH, ZIP_WIDTH) <=> zip
        when 0 then return middle
        when -1 then low = middle + 1
        else high = middle - 1
        end
      end
      nil
    end

    private

    def place index
      @places.byteslice @offsets[index], @offsets[index + 1] - @offsets[index]
    end

    # Parsing allocates, but only transiently; what survives is four packed
    # structures. Guarded so concurrent requests cannot both build it.
    def load_data
      return if defined?(@count) && @count

      (@mutex ||= Mutex.new).synchronize do
        next if defined?(@count) && @count

        build
      end
    end

    def build
      zips = +''
      places = +''
      lats = []
      lons = []
      offsets = [0]

      File.foreach PATH do |line|
        next if line.start_with? '#'

        zip, lat, lon, city, state = line.chomp.split ',', 5
        next unless zip

        zips << zip
        lats << lat.to_f
        lons << lon.to_f
        places << "#{city},#{state}"
        offsets << places.bytesize
      end

      @zips = zips.freeze
      @places = places.freeze
      @lats = lats
      @lons = lons
      @offsets = offsets
      @count = lats.size
    end
  end
end
