# frozen_string_literal: true

require_relative '../database'

namespace :db do
  desc 'Run database migrations'
  task :migrate do
    puts 'Running database migrations...'
    Sequel.extension :migration
    Sequel::Migrator.run(DB, 'db/migrations')
    puts 'Migrations complete!'
  end

  desc 'Create a new migration'
  task :create_migration, [:name] do |_t, args|
    name = args[:name] || raise('Migration name required: rake db:create_migration[migration_name]')
    timestamp = Time.now.strftime('%Y%m%d%H%M%S')
    filename = "#{timestamp}_#{name}.rb"
    filepath = "db/migrations/#{filename}"

    migration_content = <<~RUBY
      # frozen_string_literal: true

      Sequel.migration do
        up do
          # Add your migration code here
        end

        down do
          # Add rollback code here
        end
      end
    RUBY

    File.write(filepath, migration_content)
    puts "Created migration: #{filepath}"
  end

  desc 'Reset database (drop and recreate)'
  task :reset do
    puts 'Resetting database...'
    DB.drop_table?(:schema_migrations)
    Dir.glob('db/*.db').each { |file| File.delete(file) }
    Rake::Task['db:migrate'].invoke
    puts 'Database reset complete!'
  end
end
