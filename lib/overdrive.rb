# frozen_string_literal: true

# methods and constants for overdrive
module Overdrive
  API_URI     = 'https://api.overdrive.com/v1'
  MAPBOX_URI  = 'https://www.overdrive.com/mapbox/find-libraries-by-location'
  OAUTH_URI   = 'https://oauth.overdrive.com'

  KEY         = ENV.fetch 'OVERDRIVE_KEY'
  SECRET      = ENV.fetch 'OVERDRIVE_SECRET'
end
