# frozen_string_literal: true

require 'dotenv/load'

task default: :test

desc 'Run the specs'
task :test do
  sh 'ruby spec/*.rb'
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

namespace :assets do
  desc 'Update the routes metadata'
  task :precompile do
    sh 'roda-parse_routes -f routes.json app.rb'
  end
end
