# frozen_string_literal: true

require 'rake/testtask'

task default: :test

Rake::TestTask.new do |test|
  test.pattern = 'spec/**/*_spec.rb'
  test.warning = false
end

# Database tasks removed - using session-based approach for now

namespace :routes do
  desc 'Update the routes.json metadata file'
  task :update do
    sh 'roda-parse_routes -f routes.json app.rb'
  end
end
