# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

ENV['DATABASE_URL'] ||= case ENV['RACK_ENV']
when 'test'
  'postgres:///yonderbook_test'
when 'production'
  'postgres://dgesgutahlfosp:2f49d8670ce6b75a233b79bc26e92894d7bc3b9470a534bd9242638a44184f8b@ec2-107-20-214-99.compute-1.amazonaws.com:5432/d6e5hn0os8do75'
else
  'postgres:///yonderbook_development?user=yonderbook'
end
