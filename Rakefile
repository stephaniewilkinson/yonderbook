# frozen_string_literal: true

require 'rake/testtask'

task default: :test

Rake::TestTask.new do |test|
  test.pattern = 'spec/**/*_spec.rb'
  test.warning = false
end

namespace :db do
  task :create_user do
    sh 'createuser -U postgres bookmooch || true'
  end

  desc 'Setup development and test databases'
  task create: %i[create_user] do
    sh 'createdb -U postgres -O bookmooch bookmooch_development'
    sh 'createdb -U postgres -O bookmooch bookmooch_test'
  end

  desc 'Drop the development and test databases'
  task :drop do
    sh 'dropdb bookmooch_development'
    sh 'dropdb bookmooch_test'
  end

  desc 'Migrate development and test databases'
  task :migrate do
    original_env = ENV['RACK_ENV']
    %w[test development].each do |env|
      ENV['RACK_ENV'] = env
      Dir['migrate/*'].sort.each do |migration|
        sh "ruby #{migration}"
      end
    end
    ENV['RACK_ENV'] = original_env
  end
end

namespace :routes do
  desc 'Update the routes.json metadata file'
  task :update do
    sh 'roda-parse_routes -f routes.json app.rb'
  end
end
