# frozen_string_literal: true

require 'rollbar/rake_tasks'
require 'dotenv/load'

task :environment do
  Rollbar.configure do |config|
    config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
  end
end

task :default do
  sh 'ruby spec/*.rb'
end

task :migrate do
  Dir['migrate/*'].sort.each do |migration|
    sh "ruby #{migration}"
  end
end

namespace :assets do
  desc 'Update the routes metadata'
  task :precompile do
    sh 'roda-parse_routes -f routes.json app.rb'
  end
end
