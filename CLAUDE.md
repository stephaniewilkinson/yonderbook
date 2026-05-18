# Yonderbook - Project Information for Claude

## Project Overview
Yonderbook is a Ruby web application that provides tools for bookworms to analyze their Goodreads shelves and integrate with other book services like BookMooch and library systems via OverDrive.

## User Preferences
- **NEVER ignore bugs** - Always investigate and fix bugs completely rather than working around them or providing temporary solutions
- **NEVER commit code** - The user handles all git commits themselves. Do NOT use git commit commands under any circumstances.
- **NEVER run migrations without permission** - Always ask before running `bundle exec rake db:migrate`. The user controls when database schema changes are applied.
- **NEVER modify .rubocop.yml** - Do not change RuboCop configuration. If code triggers a RuboCop offense, refactor the code to satisfy the linter instead of adjusting the rules.

## Known Issues & Workarounds

### OpenSSL 3.6.0 SSL Certificate Issue (TEMPORARY WORKAROUND)
**Issue**: OpenSSL 3.6.0 (released Oct 1, 2025) breaks Ruby's Net::HTTP with "certificate verify failed (unable to get certificate CRL)" errors
**GitHub Issue**: https://github.com/ruby/openssl/issues/949
**Current Workaround**: Using OpenSSL 3.5 instead of 3.6
**Action Required**: Check GitHub issue periodically - when closed/fixed, upgrade back to latest OpenSSL:
```bash
# When issue is resolved, run:
brew upgrade openssl@3
ruby-install ruby-3.3.6 -- --with-openssl-dir=/usr/local/opt/openssl@3
```

## Framework & Technology Stack
- **Framework**: Roda (lightweight Ruby web framework)
- **Ruby Version**: 3.3.6
- **Server**: Falcon (async HTTP server)
- **Database**: PostgreSQL with Sequel ORM (Phase 1 migration from session-based)
- **Authentication**: Rodauth with email/password (OAuth deprecated)
- **Testing**: Minitest with Capybara for integration tests
- **Cache**: Custom tuple space implementation (`lib/tuple_space.rb`)
- **Styling**: CSS assets compiled via Roda assets plugin

## Key Files & Structure
```
app.rb                 # Main Roda application with all routes
lib/
  ├── auth.rb         # OAuth authentication helpers
  ├── bookmooch.rb    # BookMooch integration
  ├── cache.rb        # Session caching layer
  ├── goodreads.rb    # Goodreads API integration & data analysis
  ├── overdrive.rb    # Library/OverDrive integration
  └── tuple_space.rb  # DRb-based caching implementation
views/
  ├── layout.erb      # Main layout template
  ├── welcome.erb     # Landing page
  ├── about.erb       # About page
  ├── availability.erb # Library book availability
  ├── bookmooch.erb   # BookMooch results
  ├── library.erb     # Library selection
  └── shelves/        # Shelf-related views
```

## Development Commands
- **Start server (dev)**: `bundle exec rackup` (development server)
- **Start server (prod)**: `bundle exec falcon` (production async server)
- **Run tests**: `bundle exec rake` (default task, ~2-4 minutes runtime)
- **Database setup**: `bundle exec rake db:migrate`
- **Database migrations**: `bundle exec rake db:migrate` (uses environment-aware DB path)
- **Code quality**: `bundle exec rubocop` (available in dev/test groups)
- **Route updates**: `bundle exec rake routes:update` (updates routes.json)
- **Database access (production)**: `psql $DATABASE_URL` (in Render shell)
- **Database access (development)**: `psql postgres://localhost/yonderbook_dev`

## Testing & Performance
- **Server URL**: https://localhost:9292 (Falcon serves HTTPS by default)
- **Server Type**: Falcon async HTTP server with threaded container (4 threads)
- **Modal Testing**: Materialize v2.x uses `M.Modal.init()` instead of jQuery `.modal()`
- **Background Images**: Progressive loading implemented for better perceived performance
- **Font Loading**: Custom fonts use `font-display: swap` to prevent layout shifts
- **Asset Pipeline**: Roda assets plugin with preloading support enabled
- **Lighthouse Audits**: `lighthouse https://localhost:9292 --chrome-flags="--ignore-certificate-errors"`
- **Performance Baseline**: FCP: 3.7s, LCP: 10.8s, Speed Index: 6.9s (post-optimization)

## Testing Notes
- **Framework**: Minitest with Capybara for browser testing
- **Test command**: `rake` (not `bundle exec rake test`)
- **Lint command**: `bundle exec rubocop`
- **Runtime**: Approximately 2-4 minutes for full test suite
- **CRITICAL WORKFLOW**: The user typically has the development server running continuously. You MUST ALWAYS ask the user to turn off their server before running tests, as tests will fail with "Address already in use" errors if the server is running on port 9292.
- **REQUIRED STEP**: Before every `bundle exec rake` or test run, explicitly ask: "Please turn off your development server so the tests can run without port conflicts."
- **Goodreads OAuth Testing**: The OAuth flow requires TWO clicks: (1) First click "Connect with Goodreads" -> user goes to Goodreads, signs in via Amazon auth portal, but STAYS on Goodreads. (2) User returns to app and clicks "Connect with Goodreads" AGAIN -> this second click triggers Goodreads to redirect to `/auth` with OAuth tokens appended to the URL, completing authentication.
- **OAuth Status**: Goodreads OAuth works but requires the user to click the auth link twice - first time authorizes and stays on Goodreads, second time redirects back to `/auth` with tokens.
- **Integration Test Requirements**: Tests require real Goodreads OAuth credentials in .env (GOODREADS_USER_ID, GOODREADS_ACCESS_TOKEN, GOODREADS_ACCESS_TOKEN_SECRET). These are obtained after completing OAuth flow manually.
- **NO MOCKING**: Never mock API calls in tests - always use real API credentials and responses
- **NEVER skip tests** - All tests must remain active and passing, even if they require workarounds
- **NEVER EVER SKIP TESTS** - Under no circumstances should tests be skipped using skip() - fix them instead
- **ZERO TOLERANCE**: A single test failure is unacceptable - all tests must pass completely
- **Common issues**: Port conflicts (kill existing `falcon` servers on port 9292)
- **Debug port conflicts**: `lsof -i :9292` and `kill <PID>` if needed
- **Background testing**: Use `time bundle exec rake` to measure performance
- **OAuth Links with target="_blank" Break Tests**: Adding `target="_blank"` to OAuth authorization links causes Capybara/Selenium tests to fail because Capybara doesn't automatically follow links that open in new tabs/windows. OAuth links (like the Goodreads "Connect with Goodreads" button) must NOT have `target="_blank"` or automated tests will fail. This was discovered during the `/auth/*` to `/connections/goodreads/*` migration - tests passed at commit 1a57e0f but failed after commit 1edbbd5 added `target="_blank"` to views/connect_goodreads.erb:82.

## Environment Setup
- Copy `.env-example` to `.env` and configure API keys for:
  - Goodreads API (Note: OAuth is NOW WORKING! Users can successfully connect their Goodreads accounts. The API itself is deprecated as of December 2020, but OAuth authentication still functions properly.)
  - OverDrive API
  - BookMooch credentials
  - Resend API key (for transactional emails from app@yonderbook.com: account verification, password reset)
  - Session secret

## Architecture Notes
- **Session Management**: Uses secure session cookies with UUID session IDs
- **Caching Strategy**: Two-layer caching (session cache + tuple space for persistence). TupleSpace TTL is 30 minutes with a 10-minute reaper cycle.
- **Homepage**: The `GET /` route must NOT make any external API calls (e.g., Goodreads OAuth). It's a static marketing page. External calls on unauthenticated routes cause memory leaks from bots/monitors creating disposable sessions.
- **Error Handling**: Redirects to root on OAuth/general errors in production
- **Security**: HSTS headers, secure session handling, host redirects
- **Database**: PostgreSQL with custom migration system

## Route Structure
All routes documented in `/routes.json` via roda-route_list plugin:
- `/` - Landing/login page
- `/auth/shelves` - Goodreads shelf selection & analysis
- `/auth/shelves/:shelf/bookmooch` - BookMooch integration
- `/auth/shelves/:shelf/overdrive` - Library system integration
- `/auth/availability` - Book availability results
- `/auth/library` - Local library selection

## Testing
- **Framework**: Minitest with Capybara for browser testing
- **Test files**: `spec/` directory with web and lib test suites
- **Pattern**: `spec/**/*_spec.rb`
- **Selenium**: Available for full browser testing
- **API Credentials**: Tests have access to real API credentials via .env file (Goodreads, OverDrive, BookMooch)
- **Known Issue**: The Goodreads integration test currently fails because OAuth callback doesn't work - manual intervention required

## Code Style & Conventions
- **Frozen strings**: All files use `# frozen_string_literal: true`
- **Indentation**: 2 spaces
- **Linting**: RuboCop with performance rules
- **RuboCop Policy**: NEVER disable RuboCop warnings - always refactor code to satisfy the linter
- **Route comments**: Routes documented inline (e.g., `# route: GET /path`)
- **Error handling**: Rescue blocks redirect to root in production
- **Variable naming**: Instance variables for view data (e.g., `@shelves`, `@book_info`)

## Dependencies of Note
- `area` - Geographic/zip code handling
- `gender_detector` - Author gender analysis for book statistics
- `oauth`/`oauth2` - API authentication
- `nokogiri` - HTML/XML parsing
- `falcon-capybara` - Async server testing integration

## Git Commit Guidelines
- **Attribution**: Never attribute commits to Claude/AI assistants
- **Message format**: Capitalize first letter, use imperative mood, keep under 50 characters
- **Review**: Always show commit message before committing for approval
- **Branch naming**: This repo uses `main` as the primary branch, NOT `master`

## Architecture Migration (Emergency Phase)

**Current Status**: Goodreads API deprecated (December 2020), but OAuth authentication still works (requires two manual clicks).

**Migration Strategy**: Session-based → Database-based with required accounts
- **Phase 1**: Emergency data capture before API shutdown
- **Legal Compliance**: Can only store user's own OAuth-authenticated data permanently
- **Business Model**: Freemium SaaS ($7/month premium auto-checkout)

**Planning Documents** (located in `/planning/`):
- **`IMPLEMENTATION_PLAN.md`**: Complete project roadmap and business model
- **`database_design.md`**: Schema design with legal compliance requirements
- **`Authentication.md`**: Rodauth configuration and required account strategy
- **`TODO.md`**: Original technical roadmap and feature list

## User Preferences
- **Git status**: User wants to see full output when running `git status` in bash (don't truncate or summarize)

## Tailwind CSS Guidelines
- **NEVER manually define Tailwind color shades** (e.g., bg-brand-50, bg-brand-500, bg-brand-700)
- **NEVER create custom CSS utilities that duplicate existing functionality**
- **ALWAYS check existing classes before creating new ones** - search the codebase and git history
- **Use standard Tailwind color classes** (bg-red-500, bg-blue-600, bg-emerald-600, etc.)
- **Only define custom base colors if absolutely necessary**, let Tailwind handle shade variations
- **When changing button colors, use existing Tailwind classes** rather than inventing custom utilities
- **ONLY use established brand colors** - do not introduce new color families (like "rose") without permission
- **Ask permission before introducing new color schemes** that aren't part of the existing brand palette
- **Principle**: Audit existing styles first, reuse what's there, avoid duplication, stick to brand colors

## CSS Development Workflow
- **ALWAYS search first**: Run `grep -r "class-name" .` before adding any CSS
- **Check existing CSS file**: Read through styles.css to understand what's already defined
- **Question assumptions**: When thinking "I need to add X", first ask "Does X already exist?"
- **Follow the documented workflow**: Search existing → Check git history → Only add if nothing suitable exists
- **Remember recent context**: Don't repeat mistakes that were just corrected
- **Core principle**: Solve by reusing, not by adding. Prevent CSS bloat and inconsistency.

## Rating Calculations
- When calculating shelf averages, EXCLUDE unrated books (rating = 0)
- Unrated books should NOT be counted as 0-star ratings in average calculations
- Use `.reject { |k, v| k == 0 }` to filter out unrated books before calculating averages

## BookMooch API Rate Limits
- **Do not send more than 10 requests/second** to BookMooch (or serialize requests)
- BookMooch will rate-limit with 302 redirects if you exceed this

## BookMooch User Awareness
- **Assume users are unfamiliar with BookMooch** - it is not a popular or well-known site
- **Always explain what BookMooch is** when mentioning it (e.g., "a book trading community", "book swapping site")
- **Provide context** about how it works (trade books with other readers, get notifications when books become available)
- **Don't assume knowledge** of book trading/swapping concepts
- **Notification accuracy**: BookMooch emails users when requested books become available, not "instant alerts"
- **Points system**: Users need points to request books - complete point transactions:
  - Add a book to inventory: +0.1 points
  - Give away book (within country): +1 point
  - Mooch a book (within country): -1 point
  - Give away book (to another country): +3 points
  - Mooch a book (from another country): -3 points
- **2:1 ratio requirement**: Must send out at least 1 book for every 2 received (international sending counts as 3 books)
- **Feedback system**: Bad feedback score can lead to refused mooch requests - good packaging and response time are important
- **Lost mail policy**: Sender keeps points, receiver doesn't lose points, but limited occurrences allowed to prevent fraud
- **Request process**: It's a 3-step process, not "one-click" - users must have sufficient points AND maintain good ratios/feedback

## Design & Visual Identity
- **Overall vibe**: Whimsical and friendly
- **Imagery theme**: Birds, clouds, and other whimsical elements
- **Book aesthetics**: Old page effects, filters, bookmark textures, vintage book elements
- **Avoid**: Too many literal book icons - prefer atmospheric book-inspired effects
- **Style direction**: More artistic and whimsical than corporate or technical

## Hosting Environment
- **Platform**: Render (web service hosting, Starter plan — 512MB RAM)
- **Production Shell Access**: Available via Render dashboard shell or CLI
- **Start Command**: `bundle exec falcon serve --threaded -n 4 -b http://0.0.0.0:${PORT}`
- **Pre-deploy Command**: `bundle exec rake db:migrate` (runs on separate compute, not the web service's 512MB)
- **Health Check**: Render health check path is `/health` (lightweight, no sessions/OAuth/analytics)
- **Database**: Render Managed PostgreSQL (Basic-256mb), connected via `DATABASE_URL` env var
- **Testing Preference**: Always prefer running tests/debugging via production shell rather than deploying temporary code that needs to be reverted
- **Environment Variables**: Set via Render dashboard Environment tab, triggers auto-redeploy on changes
- **Debugging Approach**: Use production shell for testing email, database queries, API calls, etc. instead of adding temporary routes to codebase

## User Preferences
- **Editor**: Zed
- **Sort lines shortcut**: `Cmd+Option+S` (custom keybinding for alphabetizing selected lines)
- **Git status**: User wants to see full output when running `git status` in bash (don't truncate or summarize)
- **Git workflow**: Never use git revert commands when you could instead undo changes and commit the right thing. Always prefer making correct commits rather than reverting incorrect ones.