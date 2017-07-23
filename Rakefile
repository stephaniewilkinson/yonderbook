# frozen_string_literal: true

require 'rollbar/rake_tasks'

task :app do
  require_relative 'app'
end

Dir['lib/tasks/*.rb'].sort.each do |path|
  require_relative path
end

task :environment do
  Rollbar.configure do |config|
    config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
  end
end

namespace :assets do
  desc 'Precompile the assets'
  task :precompile do
    require_relative 'app'
    App.compile_assets
  end
end
