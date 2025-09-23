# Yonderbook Technical TODO

## Project Vision
Transform Yonderbook into an "Own Your Book Data" platform that aggregates reading data across all platforms (Kindle, Goodreads, Libby, Audible, etc.)

**Current Status**:
- 586 active users (last 12 months)
- Goodreads import: FIXED ✅
- BookMooch integration: Working
- Libby integration: Working
- No database currently (stateless)
- No user emails/auth

## Phase 1: Database & Auth Foundation

### Database Setup (Supabase)
- [ ] Create Supabase project (free tier: 500MB, 50k MAU)
- [ ] Design schema:
  ```sql
  -- Users table
  -- Books table (store aggregated data)
  -- User_books junction table
  -- Sources table (where each book came from)
  -- Import_jobs table (track import status)
  -- Bookclubs table (future feature)
  -- Club_members junction table
  -- Club_books table
  ```
- [ ] Set up Row Level Security (RLS) policies
- [ ] Create database functions for common operations
- [ ] Set up realtime subscriptions for relevant tables

### Authentication Implementation
- [ ] Email/password authentication setup
- [ ] Google OAuth integration
- [ ] Magic link authentication option
- [ ] Session management
- [ ] Password reset flow
- [ ] Email verification

### User Migration Strategy
- [ ] Keep app working without login (current functionality)
- [ ] Add optional "Save your data" signup
- [ ] Create migration path for anonymous to authenticated users
- [ ] Implement feature flags for gradual rollout

## Phase 2: Core Features Implementation

### Data Import System

#### Goodreads Import (Enhance Existing)
- [ ] Improve CSV parser robustness
- [ ] Handle all Goodreads export fields
- [ ] Add progress tracking for large imports
- [ ] Background job processing for imports > 100 books

#### Kindle Import
- [ ] Parse Amazon "Manage Your Content" export
- [ ] Handle purchase vs. reading status
- [ ] Extract reading progress data if available
- [ ] Match Kindle editions to other book records

#### Additional Platform Imports
- [ ] StoryGraph CSV parser
- [ ] LibraryThing export handler
- [ ] Audible listening history
- [ ] Apple Books import (research feasibility)
- [ ] Google Books API integration
- [ ] OpenLibrary API integration
- [ ] ISBN database integration

### Data Management Features
- [ ] Duplicate detection algorithm:
  ```ruby
  # Match by ISBN first
  # Fuzzy match title + author
  # Handle different editions
  # Merge duplicate records
  ```
- [ ] Master book record creation
- [ ] Source tracking system
- [ ] Data export in multiple formats (CSV, JSON, Goodreads-compatible)
- [ ] Bulk operations interface
- [ ] Manual book entry form
- [ ] Barcode lookup implementation

## Phase 3: Advanced Features

### Bookclub System
- [ ] Club creation and management
- [ ] Member invitation system
- [ ] Book voting mechanism
- [ ] Meeting scheduler with timezone handling
- [ ] Discussion threads
- [ ] Reading progress tracking per club
- [ ] Club statistics dashboard

### Sync & Background Jobs
- [ ] Implement job queue (Supabase Edge Functions or separate service)
- [ ] Scheduled sync from external platforms
- [ ] Webhook handlers for real-time updates
- [ ] Rate limiting for external API calls
- [ ] Retry logic with exponential backoff
- [ ] Error reporting and monitoring

### API Development
- [ ] RESTful API for user data access
- [ ] GraphQL endpoint (optional)
- [ ] API key management
- [ ] Rate limiting per user
- [ ] Webhook system for third-party integrations
- [ ] API documentation

## Phase 4: Platform Expansion

### iOS App Development
- [ ] React Native or Swift setup
- [ ] Barcode scanner implementation
- [ ] Camera permissions handling
- [ ] Offline data storage
- [ ] Sync with web platform
- [ ] Push notifications setup
- [ ] App Store submission

### Media Mail Integration
- [ ] PirateShip API integration
- [ ] Address validation
- [ ] Shipping label generation
- [ ] Rate calculation
- [ ] Tracking number storage
- [ ] Bulk label printing

### Performance Optimizations
- [ ] Database indexing strategy
- [ ] Implement caching layer (Redis)
- [ ] CDN setup for static assets
- [ ] Image optimization for book covers
- [ ] Lazy loading for large lists
- [ ] Pagination implementation
- [ ] Query optimization

## Technical Infrastructure

### Frontend Improvements
- [ ] Convert to React/Vue for better state management
- [ ] Implement Progressive Web App (PWA)
- [ ] Add offline functionality
- [ ] Responsive design improvements
- [ ] Accessibility audit and fixes
- [ ] Dark mode support

### Backend Architecture
- [ ] Migrate from stateless to stateful architecture
- [ ] Implement service layer pattern
- [ ] Add comprehensive error handling
- [ ] Set up logging system
- [ ] Implement monitoring (Sentry or similar)
- [ ] Add health check endpoints

### Security Implementation
- [ ] Input validation on all forms
- [ ] SQL injection prevention
- [ ] XSS protection
- [ ] CSRF tokens
- [ ] Rate limiting
- [ ] API authentication
- [ ] Secure password storage
- [ ] Data encryption for sensitive information

## Testing & Quality Assurance

### Testing Strategy
- [ ] Unit tests for data parsers
- [ ] Integration tests for API endpoints
- [ ] End-to-end tests for critical flows
- [ ] Performance testing for imports
- [ ] Load testing for concurrent users
- [ ] Security testing

### CI/CD Pipeline
- [ ] GitHub Actions setup
- [ ] Automated testing on PR
- [ ] Staging environment deployment
- [ ] Production deployment pipeline
- [ ] Database migration automation
- [ ] Rollback procedures

## Data & Analytics

### Analytics Implementation
- [ ] User behavior tracking
- [ ] Feature usage metrics
- [ ] Import success/failure rates
- [ ] API endpoint performance
- [ ] Error tracking
- [ ] Custom reading statistics calculations

### Admin Dashboard
- [ ] User management interface
- [ ] System health monitoring
- [ ] Import job monitoring
- [ ] Error log viewer
- [ ] Database statistics
- [ ] Feature flag management

## Technical Debt & Improvements

### Current Fixes Needed
- [ ] Improve error handling for API failures
- [ ] Add retry logic for rate-limited requests
- [ ] Cache book data to reduce API calls
- [ ] Sanitize user inputs
- [ ] Fix memory leaks in long-running imports
- [ ] Optimize image loading

### Code Quality
- [ ] Refactor to follow DRY principles
- [ ] Extract common functions to utilities
- [ ] Implement proper logging
- [ ] Add code comments and documentation
- [ ] Set up linting rules
- [ ] Code review process

## Integration Research

### APIs to Investigate
- [ ] Libby API commercial usage rights
- [ ] Amazon Kindle export capabilities
- [ ] StoryGraph API availability
- [ ] BookMooch API improvements
- [ ] Library systems integration options
- [ ] Publisher APIs for book metadata

### Technical Feasibility Studies
- [ ] Webscraping fallbacks for closed APIs
- [ ] Browser extension for direct imports
- [ ] Email parsing for purchase confirmations
- [ ] OCR for physical book scanning
- [ ] Blockchain for data ownership (research only)

## Documentation

### Developer Documentation
- [ ] API documentation
- [ ] Database schema documentation
- [ ] Setup instructions
- [ ] Deployment guide
- [ ] Contributing guidelines
- [ ] Architecture decisions record

### User Documentation
- [ ] Import guides per platform
- [ ] FAQ section
- [ ] Video tutorials
- [ ] Troubleshooting guide
- [ ] Privacy policy
- [ ] Terms of service

## Notes for Claude Code

When implementing features:
- Keep existing stateless functionality as fallback
- Use feature flags for gradual rollout
- All imports should handle malformed data gracefully
- Consider rate limiting for expensive operations
- Background jobs for data imports using Supabase Edge Functions
- Cache external API calls aggressively
- Use database transactions for multi-table operations
- Implement proper error boundaries in React components
- Follow RESTful conventions for API endpoints
- Use environment variables for all configuration
- Implement proper logging at all levels
- Consider mobile-first for all new features