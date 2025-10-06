# frozen_string_literal: true

require 'rake/testtask'

task default: :test

Rake::TestTask.new do |test|
  test.pattern = 'spec/**/*_spec.rb'
  test.warning = false
end

# Load database tasks
Dir.glob('lib/tasks/*.rake').each { |file| load file }

namespace :routes do
  desc 'Update the routes.json metadata file'
  task :update do
    sh 'roda-parse_routes -f routes.json app.rb'
  end
end
