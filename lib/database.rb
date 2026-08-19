# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'sequel'

rack_env = ENV.fetch('RACK_ENV', 'development')

# Production keeps the database on Render's persistent disk, development in db/,
# and tests run against a throwaway in-memory database (nil path).
sqlite_path = case rack_env
when 'production' then '/var/data/production.db'
when 'test' then nil
else 'db/development.db'
end

FileUtils.mkdir_p File.dirname(sqlite_path) if sqlite_path

# Deliberately NOT Sequel's :timeout option -- it uses sqlite3_busy_timeout,
# which retries while holding the GVL, starving the thread that holds SQLite's
# write lock so it never reaches its COMMIT. Raising :timeout makes that
# deadlock worse, not better. busy_handler_timeout releases the GVL, and
# clears busy_timeout, so `PRAGMA busy_timeout` reads back as 0 here.
DB = Sequel.sqlite(
  sqlite_path,
  foreign_keys: true,
  synchronous: :normal,
  temp_store: :memory,
  after_connect: proc { |conn| conn.busy_handler_timeout = 10_000 }
)

# WAL lets readers run alongside the writer. Persistent, but set on every boot
# so a restored database is never left in rollback-journal mode. In-memory
# databases only support the `memory` journal.
DB.run 'PRAGMA journal_mode = WAL' if sqlite_path

# A deferred transaction that reads then writes has to upgrade its lock, and
# SQLite refuses that with an instant SQLITE_BUSY no busy handler may retry.
DB.transaction_mode = :immediate

# Enable SQL logging in development only
DB.loggers << Logger.new($stdout) if rack_env == 'development'
