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

Tests require environment variables — copy `.env-example` to `.env` and fill in
values. The values no longer have to be real: the suite reaches no external
service, so placeholders are enough.

### HTTP mocking

Every call to Goodreads, OverDrive, BookMooch and OpenLibrary is stubbed at the
HTTP layer, and `WebMock.disable_net_connect!` makes an unstubbed one fail the
spec by name rather than quietly going out to the network.

Almost all of this app's requests go through `Async::HTTP` rather than
`Net::HTTP`, in three shapes (`Internet.get`, `Internet.new`, `Client.new`).
WebMock's `async_http_client` adapter swaps the `Async::HTTP::Client` constant,
and `Internet#make_client` resolves that constant at call time, so one swap
covers all three. The `oauth` gem and `resend` (via HTTParty) use `Net::HTTP`
and are covered by the adapter for that.

- `spec/support/http_mocking.rb` — WebMock and VCR configuration, plus
  `HttpFixtures` builders for the response shapes the parsers expect.
- `spec/support/default_external_apis.rb` — the defaults every `spec/web` spec
  starts from, so a browser spec driving a whole flow does not have to restate
  them. A spec that cares about one response calls `stub_request` itself; the
  later stub wins.

Two things to know when writing a stub. `Async::HTTP::Internet` adds
`Accept-Encoding: gzip, identity`, which does not affect a plain
`stub_request(:get, url)` but must be included in any stub using
`.with(headers:)`. And `WebMock::NetConnectNotAllowedError` descends from
`Exception`, not `StandardError`, so the `rescue StandardError` guards in `lib/`
cannot swallow it — an unstubbed call fails the spec instead of being reported
as an application error.

### Cassettes

`spec/fixtures/cassettes/` holds recorded responses for payloads too large to
hand-build — currently a 250-book Goodreads shelf across three pages. Use
`with_cassette('name') { ... }`; VCR is off otherwise, so everything else gets
WebMock's error, which names the request and prints a ready-to-paste stub.

Delete a cassette and run with real credentials to re-record it. Credentials are
filtered out on the way in.

### Specs that need the network

Two specs in `spec/web/system_spec.rb` drive the browser to goodreads.com and
through Amazon's sign-in. That traffic belongs to the browser process, so
WebMock can neither block nor stub it. They skip unless `LIVE_EXTERNAL_SPECS=1`
is set, and they need real credentials and a Goodreads account with the right
shelves. They are also the specs #1329 is about, which used to fail about a
third of main's runs and block deploys.

One known flake remains: `root route::GET / sends a logged-in user to their home
page` fails intermittently on browser/session timing. It predates this setup and
is not related to HTTP mocking.

## Key Files

- `app.rb` — Main Roda application class with routing, plugins, and Rodauth config
- `config.ru` — Rack config; loads Sentry, sets up env-specific middleware
- `lib/sentry_capture.rb` — Outermost middleware; reports what the stack above the app raises
- `lib/sentry_scrubber.rb` — `before_send` hook; drops request data and redacts credentials
- `lib/sentry_tracing.rb` — Opt-in latency measurement for the Goodreads and OverDrive routes
- `Rakefile` — Defines `precompile`, `tailwind:build`, `tailwind:watch`, and loads `lib/tasks/*.rake`
- `lib/database.rb` — Sequel/SQLite setup; creates DB constant, path depends on `RACK_ENV`
- `lib/cgi_parse_shim.rb` — Restores `CGI.parse`, removed in Ruby 4.0 and still called by the `oauth` gem
- `lib/tasks/db.rake` — Database rake tasks (migrate, reset, create_migration)

TODO: Clearly display the Goodreads name or logo on any location where Goodreads data appears. For instance if you are displaying Goodreads reviews, they should either be in a section clearly titled "Goodreads Reviews", or each review should say "Goodreads review from John: 4 of 5 stars..."

TODO: Link back to the page on Goodreads where the data data appears. For instance, if displaying a review, the name of the reviewer and a "more..." link at the end of the review must link back to the review detail page. You may not nofollow this link.

## Error Reporting (Sentry)

Configured in `config.ru`. `lib/sentry_capture.rb` reports what the middleware
stack raises, `lib/sentry_scrubber.rb` cleans events on the way out, and
`lib/sentry_tracing.rb` measures latency when it is switched on. The OOM section
below covers why the Rack integration is not used and what replaced it.

**Releases.** `config.release` comes from `RENDER_GIT_COMMIT`, which Render
exports into the runtime environment. That is what gives Sentry regression
detection (an issue reopens when it reappears in a release later than the one
that resolved it), "first seen in" as a deploy rather than a timestamp, and
suspect-commit attribution. Nil locally. Running `sentry-cli releases new` /
`set-commits` / `finalize` in the build, or installing the GitHub integration,
is what turns those SHAs into linked commits — not done yet.

**PII.** `send_default_pii` is off, and `enrich_sentry` sends a user `id`
without an email. `SentryScrubber` drops request bodies, cookies, query strings
and `env` wholesale, and redacts keys matching `/passw|secret|token|api[-_]?key|
auth|credential|session|cookie/i` anywhere else in the event. Nothing attaches
request data today, so the scrubber is not load-bearing — it is what keeps that
true through an upgrade or a careless call site. The rule for hand-set context
is `enrich_sentry_error`'s: send `request.params.keys`, never `request.params`.

**Tracing.** Off unless `SENTRY_TRACES_SAMPLE_RATE` is set, because transaction
objects hold Rack `env` references. `SentryTracing` is the only thing that
starts a transaction, and only for `/goodreads/shelves*` and
`/goodreads/availability` — the routes that wait on Goodreads and OverDrive,
and whose timeouts (25s in `lib/request_timeout.rb`, `with_timeout(20)` in
`lib/route_helpers.rb`) were picked without a distribution to pick them from. It
never puts the transaction on a scope, so there are no child spans and no hub
clone; what it measures is end-to-end wall time.

To try it: set `SENTRY_TRACES_SAMPLE_RATE=0.05` on staging, confirm the RSS
baseline from `MemoryLogger` output first, watch RSS across a full day including
the hour the OOM usually lands, and unset the variable to roll back without a
deploy. The RSS graph is the acceptance test, not the trace data. If the curve
changes at all, leaving it off is a good outcome — it turns the reasoning in
`lib/sentry_tracing.rb` from a hypothesis into a measurement.

## Spam Prevention

The signup form uses a honeypot field to block bot registrations. A hidden `name` field is rendered off-screen — humans never see it, but bots parsing the form will fill it in. If the field has a value on POST, the request is silently redirected to the `/check-email` page without any database interaction. The bot thinks the signup succeeded.

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
- **No ISBN search at all** — measured against the live API, 2026-09-18. Not "print ISBNs don't work, digital ones do", which is what this section used to say. Nothing works:

  | attempt | result |
  | --- | --- |
  | `q=<isbn>` | 0 products, in 40 of 40 tries — using ISBNs taken off products that library holds |
  | `identifiers=<isbn>` | accepted and **silently ignored**: returns the same unfiltered first five products as sending no filter at all |
  | `identifiers=ISBN:<isbn>`, `ISBN=<isbn>` | same, silently ignored |
  | `crossRefId=<isbn>` | HTTP 400 |
  | `q=isbn:<isbn>`, `q=identifier:<isbn>` | 0 products |

  The silent-ignore is the trap: a filtered query and an unfiltered one both return five products with HTTP 200, so counting non-empty responses reads as a hit. Compare the titles returned against a control with no filter before believing any of it.

  So every lookup goes by title, and `Matching` narrows the results by author and title. Print ISBNs do appear in `otherFormatIdentifiers` on responses; they are just as unusable as search input as digital ones.
- **Rate limits are undocumented**: The [API Usage Requirements](https://developer.overdrive.com/docs/api-usage-requirements) say "honor any limitations we set" but don't publish specific numbers. The code uses `Async::Semaphore.new(16)` for concurrent requests.
- **Availability is product-ID-only**: The v2 availability endpoint requires OverDrive product IDs, not ISBNs. A two-phase lookup (search then availability) is unavoidable without a local index.

### Optimization Opportunities

**Cache ISBN-to-product-ID mappings in the database.** After the first lookup, store the mapping so repeat shelf checks skip the expensive search phase and go straight to availability batches. This would reduce repeat visits from O(n) search calls to O(new_books) searches + O(n/25) availability calls.

**Local collection index (future).** The products endpoint supports `?lastUpdateTime={timestamp}` for incremental sync. Could paginate the entire library collection into a local table, then match ISBNs locally. Initial sync: 400-3,200 calls for a typical library (10k-80k titles at 25/page), then incremental updates. Eliminates per-book search calls entirely.

### Current Implementation

Books are processed in chunks of 100 to bound memory. Each chunk completes the full pipeline (search -> expand editions -> fetch availability) before the next starts. Raw JSON response bodies are discarded after parsing. Timing and RSS memory usage are logged per-chunk for monitoring.

## OOM / Memory Management

The app runs on Render's Starter plan (512MB RAM).

### Current status: the OOM is fixed (measured 2026-09-17)

**The daily OOM kill described below no longer happens.** Everything from "Root
cause" onwards is the history of a solved problem, kept because it explains why
the mitigations exist and what to watch if it comes back.

Measured from Render's logs:

| Signal | Value |
| --- | --- |
| `MemoryLogger` request counter | #106,480 on 2026-09-12 → **#191,770** on 2026-09-17 |
| Render instance id | `xbr7b`, unchanged across 28 samples at 6h intervals over 7 days |
| RSS | 225.2MB → **229.4MB** across those ~85,000 requests |

`MemoryLogger` resets its counter to 0 on every process start
(`lib/memory_logger.rb`), so a counter climbing monotonically past 191,000 means
the process has not restarted in at least 5½ days. The instance id says the same
thing back to 2026-09-11.

RSS moved +4.2MB over ~85,000 requests. The leak documented below was 0.2-0.4MB
*per request*. Current RSS sits well under both the 400MB warning threshold and
the 512MB limit.

Two caveats. This is inferred from the request counter and instance id rather
than from Render's own restart events, and Render's log retention bounds how far
back it can be checked — seven days confirmed. It is strong evidence, not a
guarantee about earlier weeks.

To re-check:

```bash
render logs -r srv-cuhq5cpu0jms73adb27g --limit 200 -o json --confirm | grep -o '\[mem\] #[0-9]* START'
```

A number lower than the last one recorded here means the process restarted.

### Root cause

There are two layers to the problem:

**Layer 1: Per-request memory allocations that are never returned to the OS.** Every `GET /` request leaked ~0.2-0.4MB of RSS, even though the homepage is a static marketing page with no DB queries or API calls. The leak came from middleware and analytics running on every request, including bot/monitor traffic hitting `/` every minute:

- **Sentry transaction tracing** (`traces_sample_rate = 0.1`): The `CaptureExceptions` middleware clones the Sentry hub, creates a scope, stores the full Rack `env` hash in the scope, and creates transaction/span objects for 10% of requests. Under Falcon's fiber-based concurrency, hub clones stored in `Thread.current` may not clean up properly between fibers.
- **PostHog analytics on homepage**: `Analytics.track` queued a PostHog event with a unique distinct_id (new session UUID) for every bot request. Useless analytics noise that allocated objects into PostHog's internal queue.
- **Session writes for bots**: `session['session_id'] ||= SecureRandom.uuid` forced the Roda sessions plugin to encrypt and set a cookie on every request, even for bots that never send cookies back.

**Layer 2: Memory that GC cannot reclaim.** Even after Ruby's major GC collects objects (old_objects drops from 549k to 50k), RSS doesn't decrease -- it stays at 506MB and keeps climbing. This happens even with `MALLOC_ARENA_MAX=2` set, ruling out simple glibc arena fragmentation. The retained memory likely comes from C-level allocations in OpenSSL (used by Sentry's HTTP transport and session encryption) and object-slot fragmentation in Ruby's heap pages.

### Typical OOM timeline (historical, before the mitigations)

Server started at ~100MB. At 0.3MB/request with bot traffic every minute:
- ~23 hours to reach 512MB and trigger SIGKILL
- SIGKILL cannot be caught -- no Ruby error handler, no Sentry, nothing runs

The second point still holds and is why nothing in-process can report a restart.
The first no longer describes production; see "Current status" above.

### Mitigations (code changes)

**Homepage served before middleware** (app.rb) -- `r.root` is now matched before `enrich_sentry` and the `session['session_id']` assignment. Bot traffic to `/` no longer creates sessions or Sentry scopes. This eliminates the primary source of per-request allocations.

**Sentry::Rack::CaptureExceptions middleware removed** (app.rb) -- This middleware cloned the Sentry hub, created a scope storing the full Rack `env`, and ran session tracking on every request. Under Falcon's fiber/thread model, these allocations leaked ~0.2-0.4MB/request that was never reclaimed. Tracing is off by default for the same reason (see below).

Removing it also removed the only thing watching the middleware stack, so errors are captured in three places instead, none of which clone a hub:

- the rescue block at the bottom of the route tree in app.rb, which covers the route tree and most of what happens inside it
- the `error_handler` plugin, for anything that raises after that block returns -- a template raising during `view`, an error inside the rescue handler itself, anything a plugin raises above the routing tree
- `SentryCapture` (`lib/sentry_capture.rb`), outermost in config.ru, for `Rack::HostRedirect`, `Rack::Attack`, `MemoryLogger` and `RequestTimeout`. A rescue and a re-raise: no hub clone, no scope, no reference to `env` held past the call, no session tracking, no transaction.

`SentryCapture.capture_once` is what keeps the first two from sending two events for the same exception -- outside production the route rescue re-raises, and `error_handler` then sees the same object.

**Periodic GC.compact** (lib/memory_logger.rb) -- When RSS exceeds 400MB, `GC.compact` runs every 100 requests. This consolidates the Ruby heap so free pages can be returned to the OS. Won't fully solve malloc fragmentation but helps with Ruby-level fragmentation.

### Mitigations (Render env vars)

**`MALLOC_ARENA_MAX=2`** (set in Render dashboard) -- Limits glibc to 2 memory arenas instead of 8 per thread. Heroku made this the default for all Ruby apps. Already set; insufficient on its own to prevent OOM -- the Sentry middleware removal was the critical fix.

**`Process.warmup`** (config.ru, production only) -- Ruby 3.3+ API that compacts the heap and optimizes GC after boot, before serving requests.

**`RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR=1.3`** (optional) -- Triggers major GC more frequently. Sam Saffron measured ~22% RSS reduction. Causes more GC pauses, acceptable at low traffic.

### Diagnostic logging

`MemoryLogger` middleware (`lib/memory_logger.rb`) logs RSS and GC stats on every request. Runs in production only, skips `/health` and static assets. Logs twice per request -- START and END -- so the killing request is identifiable even after SIGKILL.

```
[mem] #42 START GET /goodreads/shelves rss=294.2MB
[mem] #42 END GET /goodreads/shelves status=200 duration=1234.5ms rss=312.4MB delta=+18.2MB heap_live=1823456 old_objects=982341 major_gc=1 minor_gc=3
[mem] #43 START GET /login rss=312.4MB
                                        <-- process killed here, no END line
```

**How to read the logs:** A START with no matching END is the request that caused OOM. Large positive `delta` values on END lines show which requests grow memory. The `WARNING` line fires when RSS exceeds 400MB. After the fix, look for `[mem] GC.compact` lines showing compaction results.

### Why memory still grows (post-fix)

Written when RSS was still climbing after the mitigations. The 2026-09-17
measurement puts the remaining growth at roughly 4MB per 85,000 requests, which
is slow enough that the process now outlives any plausible deploy interval. The
mechanism below is still the right explanation for the residual creep; it just
no longer adds up to a kill.

Every authenticated request runs through this pipeline (app.rb lines 108-127):

1. **Session decryption/encryption** -- Rodauth decrypts the incoming session cookie and re-encrypts the outgoing one via OpenSSL. Cipher contexts are C-level `malloc` allocations.
2. **Sentry scope calls** -- `enrich_sentry` calls `Sentry.set_user` and `Sentry.set_tags` on every request, creating scope objects on the Sentry hub even without the middleware.
3. **DB query** -- `Account[rodauth.session_value]` runs a database query on every authenticated request.

The problem isn't Ruby objects -- GC collects those fine (old_objects drops from 549k to 50k). The problem is **glibc malloc fragmentation from C-level allocations**. OpenSSL cipher contexts, Sentry internals, and database buffers are allocated via `malloc()`. When freed, they leave holes in the heap that glibc can't return to the OS. Falcon's fiber concurrency makes this worse -- fibers interleave allocations across memory pages, so no page is ever fully free.

`GC.compact` only helps Ruby heap pages. `MALLOC_ARENA_MAX=2` limits arenas but doesn't prevent fragmentation within them.

### Next steps for memory

None of these are needed while RSS holds at ~229MB. Kept for the case where
"Current status" stops being true.

**`malloc_trim` gem** -- Calls `malloc_trim()` after each major GC cycle to return freed glibc pages to the OS. ~1% CPU overhead, Linux only (which Render uses). This is the lowest-effort next step. Typical RSS reduction: 10-30%.

**jemalloc** -- A drop-in malloc replacement that returns memory to the OS far more aggressively. Used by GitLab, Discourse, and Mastodon. However, it requires a Docker deploy on Render (`apt-get install libjemalloc2` + `LD_PRELOAD`), which is overkill unless `malloc_trim` proves insufficient. Typical RSS reduction: 25-40%.

**Health-check-based restart** -- Write a custom `/health` that returns 500 when RSS > 450MB. Render restarts after 60s of failed checks. This is a fallback, not a fix.

### Noticing a restart

Nothing in this process can report its own SIGKILL, so if the OOM comes back,
the app's error reporting is structurally incapable of seeing it. That gap is
real; what changed is its urgency, since there are currently no restarts to
count.

**Render's logs already answer it, for free.** The request counter and instance
id used under "Current status" are the cheapest check available and need no
third party:

```bash
render logs -r srv-cuhq5cpu0jms73adb27g --limit 200 -o json --confirm | grep -o '\[mem\] #[0-9]* START'
```

**Sentry Uptime Monitoring** is the automated option -- dashboard configuration
rather than code, an HTTP check from Sentry's infrastructure that opens an issue
when the app stops answering and resolves when it returns. Two things to know
before setting one up:

- It is metered against the pay-as-you-go budget. With that budget at zero,
  Sentry refuses to create the monitor.
- The default failure threshold of 3, at a 1-minute interval, means downtime
  shorter than ~3 minutes never opens an issue. A Render restart is often
  quicker than that, so the defaults would miss the event being watched for.
  Use a threshold of 1, and point it at the apex domain -- `Rack::HostRedirect`
  301s `www`, and the default assertions require a 2xx.

`Sentry.capture_check_in` (Cron Monitoring) is the in-process alternative -- a
heartbeat carrying the RSS that `MemoryLogger` already samples, where a missed
beat means the process died between beats. It needs code and it costs memory,
so it is the last resort rather than the first.

### What doesn't help

- **Sentry / error_handler plugin** -- SIGKILL terminates the process before any Ruby code can execute. These only catch Ruby exceptions.
- **Reducing TupleSpace TTL** -- Cached entries are ~1-2KB each, negligible at this scale.
- **Wrapping OAuth calls in `Sync do`** -- Inside Falcon, `Sync do` is a no-op (already in an async task). Net::HTTP calls are automatically non-blocking via Ruby's fiber scheduler.
- **Removing `--verbose` from Falcon** -- Falcon's verbose middleware writes to stdout and doesn't buffer in memory.

### Investigation log (May 2026)

Observed `GET /` requests every ~1 minute growing RSS by 0.2-0.4MB with `major_gc=0 minor_gc=0` on most requests. Key data points:

```
02:58 rss=500.7MB  (WARNING threshold)
03:09 rss=506.3MB  old_objects drops 549201 -> 50934 (major GC ran, but RSS didn't shrink)
03:10 rss=507.4MB  old_objects=183943 (climbing back up)
03:13 rss=510.0MB  -> OOM kill, Render restarts process
03:14 rss=100.3MB  (fresh start, first request)
```

The fact that RSS didn't decrease after major GC -- even with `MALLOC_ARENA_MAX=2` already set -- pointed to the Sentry middleware as the primary culprit. `Sentry::Rack::CaptureExceptions` clones the hub, creates scopes, and stores the Rack env on every request. Under Falcon's fiber/thread model, these allocations aren't properly reclaimed. Fix: remove Sentry middleware (keep manual error capture), move homepage route before session/analytics middleware, add GC.compact safety net.

## Deployment (Render)

Deployed on [Render](https://render.com) with a persistent disk for SQLite at `/var/data/production.db`.

Render does not use the Procfile. Configuration lives in `render.yaml` (a Render
Blueprint); historically it was set by hand in the dashboard under Settings.

**What the live service actually runs** (read via `render services -o json` on
2026-08-27, service `srv-cuhq5cpu0jms73adb27g`):

```
build:  bundle install
start:  bundle exec falcon --verbose serve --threaded -n 2 -b http://0.0.0.0:${PORT}
```

> **⚠️ Migrations do not run on deploy.** There is no `rake db:migrate` in the
> start command and no pre-deploy command. Every schema change has to be applied
> by hand in the Render shell. An earlier version of this section documented a
> start command with `rake db:migrate &&` in front — that was the intent, but it
> was never configured on the service.
>
> `render.yaml` fixes this: it matches the live service on every field except
> `startCommand`, where it adds the migration step. Applying the Blueprint (or
> just editing the start command in the dashboard) resolves it.
>
> To see what production is actually running:
> ```
> sqlite3 /var/data/production.db "select * from schema_info"
> ```
> Note `schema_info`, not `schema_migrations` — Sequel selects `IntegerMigrator`
> for `001_`-style migration filenames, which tracks a single version integer.

The build command does **not** run `rake precompile`, so Tailwind is not rebuilt
on deploy. This works only because `assets/css/styles.css` and
`assets/compiled_assets.json` are committed. Edit `assets/css/input.css` without
rebuilding and committing the output, and production ships stale CSS.

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
