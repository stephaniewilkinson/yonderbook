# frozen_string_literal: true

require 'rake/testtask'

task default: :test

Rake::TestTask.new do |test|
  test.pattern = 'spec/**/*_spec.rb'
  test.warning = false
end

# Ensure Tailwind CSS is built before running tests
desc 'Build Tailwind CSS and run tests'
task test: 'tailwind:build'

# Load database tasks
Dir.glob('lib/tasks/*.rake').each { |file| load file }

namespace :routes do
  desc 'Update the routes.json metadata file'
  task :update do
    sh 'roda-parse_routes -f routes.json app.rb'
  end
end

namespace :tailwind do
  desc 'Build Tailwind CSS for production'
  task :build do
    require 'tailwindcss/ruby'
    sh "#{Tailwindcss::Ruby.executable} -i assets/css/input.css -o assets/css/styles.css --minify"
  end

  desc 'Watch for changes and rebuild Tailwind CSS'
  task :watch do
    require 'tailwindcss/ruby'
    sh "#{Tailwindcss::Ruby.executable} -i assets/css/input.css -o assets/css/styles.css --watch"
  end
end
