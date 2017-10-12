ENV['RACK_ENV'] ||= 'development'

ENV['DATABASE_URL'] ||= case ENV['RACK_ENV']
when 'test'
  "postgres:///bookmooch_test?user=bookmooch"
when 'production'
  "postgres:///bookmooch_production?user=bookmooch"
else
  "postgres:///bookmooch_development?user=bookmooch"
end
