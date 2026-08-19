# frozen_string_literal: true

require 'async'
require 'async/http/internet'
require 'json'
require 'uri'

class Overdrive
  # Raised when OverDrive answers with something we can't read.
  class ApiError < StandardError; end

  # Finds the OverDrive consortia near a zip code.
  #
  # Unlike the rest of Overdrive this talks to the public website rather than
  # the authenticated API, so it needs browser-ish headers and gets HTML back
  # when it is blocked or throttled.
  module LibrarySearch
    ENDPOINT = 'https://www.overdrive.com/mapbox/find-libraries-by-query'
    MAX_RESULTS = 10
    HEADERS = [
      ['user-agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'],
      ['referer', 'https://www.overdrive.com/libraries']
    ].freeze

    module_function

    # Returns [[consortium_id, name, logo_url], ...] for libraries near zip_code.
    def near zip_code
      task = Async do
        internet = Async::HTTP::Internet.new
        params = URI.encode_www_form query: zip_code, includePublicLibraries: true, includeSchoolLibraries: false
        response = internet.get "#{ENDPOINT}?#{params}", HEADERS
        [response.status, response.read]
      ensure
        internet&.close
      end

      parse(*task.wait, zip_code).first(MAX_RESULTS).map { |l| [l['consortiumId'], l['consortiumName'], l['consortiumLogo']] }
    end

    # OverDrive answers a blocked or throttled request with an HTML page rather
    # than JSON. Say which, instead of raising a bare JSON::ParserError. An
    # empty list is left alone: that legitimately means no libraries nearby.
    def parse status, body, zip_code
      summary = body.to_s.gsub(/\s+/, ' ').strip[0, 200]
      raise ApiError, "OverDrive returned HTTP #{status} for #{zip_code}: #{summary}" unless status == 200

      JSON.parse body
    rescue JSON::ParserError
      raise ApiError, "OverDrive returned non-JSON for #{zip_code}: #{summary}"
    end
  end
end
