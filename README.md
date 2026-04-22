# Yonderbook | Tools for Bookworms 📒

## Stack

- **Framework:** Roda (routing tree web toolkit) with Sequel ORM and PostgreSQL
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
psql $DATABASE_URL
```

**Development:**
```bash
psql postgres://localhost/yonderbook_dev
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
- `lib/database.rb` — Sequel/PostgreSQL setup; creates DB constant via `DATABASE_URL`
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

## OverDrive API

[OverDrive](https://developer.overdrive.com/) provides APIs for searching library digital collections and checking availability.

### Authentication

Uses OAuth2 client credentials flow via `https://oauth.overdrive.com/token`. The returned bearer token is used for all subsequent API calls. Tokens are short-lived and should be fetched per-session.

### Endpoints Used

**Library info** — `GET /v1/libraries/{consortiumId}`
Returns collection token, website ID, and homepage URL. The `collectionToken` is required for all product/availability queries.

**Product search** — `GET /v1/collections/{collectionToken}/products?q={query}`
Searches the library's digital catalog. Accepts a single query string (ISBN, title, or author). **Does not support batch/bulk queries** — there is no way to search multiple ISBNs in one call. Pagination via `limit` (default 25) and `offset`.

**Availability (v2)** — `GET /v2/collections/{collectionToken}/availability?products={id1},{id2},...`
Accepts up to **25 comma-separated product IDs** per request. Returns `copiesAvailable`, `copiesOwned`, and hold counts. Product IDs (`reserveId`) come from search results. **Cannot accept ISBNs directly** — must resolve ISBN to product ID via search first.

### Key Limitations

- **No bulk search**: Each book requires its own search API call. For a shelf of 500 books, that's 500+ search calls. This is the main bottleneck.
- **Print ISBNs are not searchable**: Goodreads shelves contain print ISBNs, but only digital ISBNs (ebook/audiobook format) are searchable via the `identifiers` parameter. Print ISBNs appear in `otherFormatIdentifiers` in responses but cannot be used as search input. This is why the code falls back to title+author matching when ISBN search returns no results.
- **Rate limits are undocumented**: The [API Usage Requirements](https://developer.overdrive.com/docs/api-usage-requirements) say "honor any limitations we set" but don't publish specific numbers. The code uses `Async::Semaphore.new(16)` for concurrent requests.
- **Availability is product-ID-only**: The v2 availability endpoint requires OverDrive product IDs, not ISBNs. A two-phase lookup (search then availability) is unavoidable without a local index.

### Optimization Opportunities

**Cache ISBN-to-product-ID mappings in the database.** After the first lookup, store the mapping so repeat shelf checks skip the expensive search phase and go straight to availability batches. This would reduce repeat visits from O(n) search calls to O(new_books) searches + O(n/25) availability calls.

**Local collection index (future).** The products endpoint supports `?lastUpdateTime={timestamp}` for incremental sync. Could paginate the entire library collection into a local table, then match ISBNs locally. Initial sync: 400-3,200 calls for a typical library (10k-80k titles at 25/page), then incremental updates. Eliminates per-book search calls entirely.

### Current Implementation

Books are processed in chunks of 100 to bound memory. Each chunk completes the full pipeline (search -> expand editions -> fetch availability) before the next starts. Raw JSON response bodies are discarded after parsing. Timing and RSS memory usage are logged per-chunk for monitoring.

## Deployment (Render)

Deployed on [Render](https://render.com) with Render Managed PostgreSQL.

Render does not use the Procfile — commands are set in the dashboard under Settings:

**Build command:**
```
bundle install && bundle exec rake precompile
```

**Pre-deploy command:**
```
bundle exec rake db:migrate
```

**Start command:**
```
bundle exec falcon --verbose serve --threaded -n 2 -b http://0.0.0.0:${PORT}
```

### Important notes

- Migrations run in the pre-deploy command on separate compute, not the web service's 512MB.
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
