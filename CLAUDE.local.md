# Yonderbook - Project Information for Claude

## Project Overview
Yonderbook is a Ruby web application that provides tools for bookworms to analyze their Goodreads shelves and integrate with other book services like BookMooch and library systems via OverDrive.

## Framework & Technology Stack
- **Framework**: Roda (lightweight Ruby web framework)
- **Ruby Version**: 3.3.6
- **Server**: Falcon (async HTTP server)
- **Authentication**: OAuth (Goodreads integration)
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
- **Start server**: `falcon`
- **Run tests**: `bundle exec rake` (default task, ~2-4 minutes runtime)
- **Database setup**: `rake db:create && rake db:migrate`
- **Code quality**: `rubocop` (available in dev/test groups)
- **Route updates**: `rake routes:update` (updates routes.json)

## Testing Notes
- **Framework**: Minitest with Capybara for browser testing
- **Runtime**: Approximately 2-4 minutes for full test suite
- **Common issues**: Port conflicts (kill existing `falcon` servers on port 9292)
- **Debug port conflicts**: `lsof -i :9292` and `kill <PID>` if needed
- **Background testing**: Use `time bundle exec rake` to measure performance

## Environment Setup
- Copy `.env-example` to `.env` and configure API keys for:
  - Goodreads API
  - OverDrive API
  - BookMooch credentials
  - Session secret
  - SendGrid (for emails)

## Architecture Notes
- **Session Management**: Uses secure session cookies with UUID session IDs
- **Caching Strategy**: Two-layer caching (session cache + tuple space for persistence)
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

## Code Style & Conventions
- **Frozen strings**: All files use `# frozen_string_literal: true`
- **Indentation**: 2 spaces
- **Linting**: RuboCop with performance rules
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