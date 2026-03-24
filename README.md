# Yonderbook | Tools for Bookworms 📒

## Stack

- **Framework:** Roda (routing tree web toolkit) with Sequel ORM and SQLite
- **Auth:** Rodauth (login, email auth/magic links, password reset, lockout)
- **Server:** Falcon (async Ruby web server), using `falcon serve` with `--threaded`
- **CSS:** Tailwind CSS, compiled via `tailwindcss-ruby` gem
- **Assets:** Roda assets plugin with precompilation (`assets/compiled_assets.json`)
- **Ruby version:** Defined in `.ruby-version`

## Installation

```
git clone git@github.com:stephaniewilkinson/yonderbook.git
cd yonderbook
cp .env-example .env # if you msg me I can share my api keys
bundle install
rake db:migrate
```

## Start the Server
`falcon`

## Database Access

**Production (Render):**
```bash
sqlite3 /var/data/production.db
```

**Development:**
```bash
sqlite3 db/development.db
```

## Testing

```
bundle exec rake test
```

Tests require environment variables — copy `.env-example` to `.env` and fill in values.

## Key Files

- `app.rb` — Main Roda application class with routing, plugins, and Rodauth config
- `config.ru` — Rack config; loads Sentry, sets up env-specific middleware
- `Rakefile` — Defines `precompile`, `tailwind:build`, `tailwind:watch`, and loads `lib/tasks/*.rake`
- `lib/database.rb` — Sequel/SQLite setup; creates DB constant, path depends on `RACK_ENV`
- `lib/tasks/db.rake` — Database rake tasks (migrate, reset, create_migration)

TODO: Clearly display the Goodreads name or logo on any location where Goodreads data appears. For instance if you are displaying Goodreads reviews, they should either be in a section clearly titled "Goodreads Reviews", or each review should say "Goodreads review from John: 4 of 5 stars..."

TODO: Link back to the page on Goodreads where the data data appears. For instance, if displaying a review, the name of the reviewer and a "more..." link at the end of the review must link back to the review detail page. You may not nofollow this link.

## BookMooch API

[BookMooch](https://bookmooch.com) is a book trading community where users can give away books they no longer need and receive books they want.

### Rate Limits

The BookMooch API allows up to **10 requests/second**. Exceeding this results in 302 redirect responses (not standard 429s). In practice, keeping requests concurrent with a connection pool limit (rather than throttling with a rate limiter) works best — a leaky bucket limiter causes timeouts and connection issues with BookMooch's server.

### GET vs POST

All API calls accept parameters via either GET (URL params) or POST (body). **Use POST for large payloads** like bulk ASIN/ISBN submissions — GET has a ~2048 character URL limit, so large ISBN lists must be batched. POST can send arbitrarily large fields in a single request.

### Error Handling

Errors are indicated by a negative `result_code` field in the XML response, with a `result_text` description:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<userids>
  <userid>
    <id>john_smith</id>
    <result_code>-1</result_code>
    <result_text>no data found</result_text>
  </userid>
</userids>
```

### Authentication

The `/api/userbook` endpoint uses HTTP Basic Auth. A 302 response means rate limiting; a 401 or HTML error page means invalid credentials (users should use their BookMooch username, not email).

## Deployment (Render)

Deployed on [Render](https://render.com) with a persistent disk for SQLite at `/var/data/production.db`.

Render does not use the Procfile — commands are set in the dashboard under Settings:

**Build command:**
```
bundle install && bundle exec rake precompile
```

**Start command:**
```
bundle exec rake db:migrate && bundle exec falcon --verbose serve --threaded -n 2 -b http://0.0.0.0:${PORT}
```

### Important notes

- Render's persistent disk (`/var/data`) is only mounted at **runtime**, not during builds. Migrations must run in the start command.
- Rake tasks in `lib/tasks/` must not `require` `database.rb` at the top level — it calls `FileUtils.mkdir_p('/var/data')` which fails during builds. Require it lazily inside task bodies that need it.
- The `precompile` task uses a bare Roda class (not the full App) to avoid loading all app dependencies during the build. `app.rb` also calls `compile_assets` at startup.
- `tailwindcss-ruby` must stay in the top-level Gemfile group (not `:development`) because it's needed by the build step.

## Routing

This app uses the [roda-route-list plugin.](https://github.com/jeremyevans/roda-route_list) This makes all the routes available in a /routes.json file.

## Creating a self-signed certificate

```
openssl req -x509 -out localhost.crt -keyout localhost.key \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=localhost' -extensions EXT -config <( \
   printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
