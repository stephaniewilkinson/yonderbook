require 'rollbar/rake_tasks'

task :app do
  require_relative 'app'
end

Dir[__dir__ + "/lib/tasks/*.rb"].sort.each do |path|
  require path
end

task :environment do
  Rollbar.configure do |config |
    config.access_token = 'ee0a8b14155148c28004d3e9b7519abd'
  end
end

namespace :assets do
  desc "Precompile the assets"
  task :precompile do
    require './app'
    App.compile_assets
  end
end
