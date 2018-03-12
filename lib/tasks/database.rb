# frozen_string_literal: true
require_relative '../db'

namespace :db do
  namespace :migrate do
    desc 'Perform migration up to latest migration available'
    task up: :app do
      Sequel.extension(:migration)
      Sequel::Migrator.run(DB, "migrations")
      puts '<= db:migrate:up executed'
    end
    desc 'Perform migration down (erase all data)'
    task down: :app do
      Sequel.extension(:migration)
      Sequel::Migrator.run(DB, 'migrate', target: 0)
      puts '<= db:migrate:down executed'
    end
  end

  desc 'Perform migration up to latest migration available'
  task migrate: 'db:migrate:up'

  desc 'Create the database'
  task create: :app do
    config = DB.opts
    config[:charset] = 'utf8' unless config[:charset]
    puts "=> Creating database '#{config[:database]}'"
    create_db(config)
    puts '<= db:create executed'
  end
  desc 'Drop the database'
  task drop: :app do
    DB.disconnect
    config = DB.opts
    puts "=> Dropping database '#{config[:database]}'"
    drop_db(config)
    puts '<= db:drop executed'
  end
end

def self.create_db(config)
  environment = {}
  environment['PGUSER']     = config[:user]
  environment['PGPASSWORD'] = config[:password]
  arguments = []
  arguments << "--encoding=#{config[:charset]}" if config[:charset]
  arguments << "--host=#{config[:host]}" if config[:host]
  arguments << "--username=#{config[:user]}" if config[:user]
  arguments << config[:database]
  Process.wait Process.spawn(environment, 'createdb', *arguments)
end

def self.drop_db(config)
  environment = {}
  environment['PGUSER']     = config[:user]
  environment['PGPASSWORD'] = config[:password]
  arguments = []
  arguments << "--host=#{config[:host]}" if config[:host]
  arguments << "--username=#{config[:user]}" if config[:user]
  arguments << config[:database]
  Process.wait Process.spawn(environment, 'dropdb', *arguments)
end
