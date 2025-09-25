# Yonderbook Technical TODO

## Project Vision
Transform Yonderbook into a premium book automation service with the feature: **"Add to TBR anywhere → Book appears in Libby automatically"**

**Current Status**:
- 586 active users (last 12 months)
- Goodreads import: FIXED ✅
- BookMooch integration: Working
- Libby integration: Working
- No database currently (stateless)
- No user emails/auth

## 🎯 Strategic Roadmap & Revenue Model

### **Business Model: Freemium SaaS**
- **Free Tier**: Cross-platform book tracking, manual library checking
- **Premium Tier**: Automatic checkout, email notifications, advanced analytics
- **Pricing**: $7/month ($70/year with discount)
- **Target**: 5-10% conversion rate = 30-60 premium subscribers = $210-420/month recurring revenue

### **Timeline & Milestones**

#### 🚨 **Phase 1: Emergency Data Capture (Weeks 1-2)**
**Goal**: Secure user data before Goodreads API shutdown
- Deploy SQLite database alongside existing cache system
- Start capturing ALL Goodreads data immediately
- Basic user accounts for data persistence
- Email collection for future notifications

#### 💰 **Phase 2: Premium Foundation (Weeks 3-8)**
**Goal**: Build monetization infrastructure
- OverDrive OAuth integration and API client
- Stripe subscription system integration
- Email service setup (SendGrid/Mailgun)
- Premium feature flags and user tiers

#### 🚀 **Phase 3: Auto-Checkout Launch (Weeks 9-12)**
**Goal**: Launch killer feature and convert users to premium
- Automatic checkout system development
- Email notification templates and preferences
- User onboarding flow for three-service setup
- Premium tier launch with free trial period

#### 📈 **Phase 4: Growth & Optimization (Month 4+)**
**Goal**: Scale and improve conversion rates
- User analytics and feature usage tracking
- A/B test pricing and onboarding flows
- Additional integrations (StoryGraph, Kindle, etc.)
- Mobile app development for broader reach

## 🚨 PHASE 1: CRITICAL - Data Capture Before Goodreads Lockout

### Emergency Database Setup (ASAP)
- [ ] Create SQLite database (start simple, fast deployment)
- [ ] Implement core schema from database_design.md:
  ```sql
  -- users, services, books, user_books, libraries, book_availability
  -- Focus on Goodreads/BookMooch/OverDrive data capture
  ```
- [ ] Create migration files for all core tables
- [ ] Deploy database system to production
- [ ] Add database writes alongside existing cache (dual-write pattern)

### Emergency Goodreads Data Preservation
- [ ] **HIGHEST PRIORITY**: Start capturing ALL Goodreads data to database
- [ ] Background job to sync existing users' Goodreads data
- [ ] Store complete Goodreads API responses (JSON blobs for backup)
- [ ] Monitor Goodreads API health/availability
- [ ] Create data export functionality (in case API goes down suddenly)
- [ ] Email existing users about potential service disruption
- [ ] Build fallback: manual Goodreads CSV import

### Minimal User Authentication (Simple Start)
- [ ] Basic email signup (no OAuth complexity yet)
- [ ] Session management for database persistence
- [ ] Link anonymous sessions to user accounts
- [ ] Keep current stateless functionality as fallback

## 🎯 PHASE 2: Build Toward Auto-Checkout Killer Feature

### Data Import System

#### Goodreads Import (Enhance Existing)
- [ ] Improve CSV parser robustness
- [ ] Handle all Goodreads export fields
- [ ] Add progress tracking for large imports
- [ ] Background job processing for imports > 100 books

#### 🎯 OverDrive OAuth Integration (THE KILLER FEATURE)
- [ ] Research OverDrive OAuth 2.0 requirements and limitations
- [ ] Register OverDrive developer account and app
- [ ] Implement OverDrive OAuth flow in existing auth system
- [ ] Store OverDrive tokens securely in services table
- [ ] Build OverDrive API client for library operations
- [ ] Test checkout/hold functionality with real library account

#### 🚀 **PREMIUM FEATURE: Automatic Checkout System**
**Value Prop: "Add to TBR anywhere → Book appears in Libby automatically"**
**Monetization: $5-10/month premium subscription**

##### Core Auto-Checkout Infrastructure
- [ ] Build webhook/polling system to detect new TBR additions
- [ ] Create availability checking pipeline (OverDrive API)
- [ ] Implement automatic checkout logic with error handling
- [ ] Handle edge cases: holds, checkout limits, unavailable books
- [ ] Implement smart queuing for users with checkout limits
- [ ] Handle library system differences and limitations

##### Premium Subscription System
- [ ] Design subscription tiers (Free vs Premium)
- [ ] Integrate payment processing (Stripe)
- [ ] Build subscription management dashboard
- [ ] Implement feature flags for premium-only features
- [ ] Create upgrade prompts and trial system
- [ ] Add billing/invoice generation

##### Email Notification System (Required for Premium)
- [ ] Set up email service (SendGrid/Mailgun)
- [ ] Build email templates for checkout notifications
- [ ] Implement notification preferences (immediate/daily digest)
- [ ] Add email verification for accounts
- [ ] Create onboarding email sequence
- [ ] Build admin email monitoring dashboard

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

### BookMooch Integration Enhancement
- [ ] Improve BookMooch batch processing efficiency
- [ ] Add BookMooch availability checking to auto-checkout flow
- [ ] Handle BookMooch points system in recommendations
- [ ] Build BookMooch wishlist sync with TBR additions

### Background Jobs & Monitoring (Critical for Auto-Checkout)
- [ ] Implement reliable job queue system
- [ ] Build retry logic with exponential backoff for API failures
- [ ] Create monitoring/alerting for auto-checkout failures
- [ ] Add rate limiting for OverDrive API calls
- [ ] Build health checks for all external APIs
- [ ] Error reporting system (email admins on failures)

## 🚧 PHASE 3: Stabilization & Growth Features

### User Experience Improvements
- [ ] Onboarding flow for three-service setup
- [ ] User dashboard showing auto-checkout statistics
- [ ] Reading analytics across all platforms
- [ ] Book recommendation engine using cross-platform data
- [ ] Advanced search across all user's books
- [ ] Reading goal tracking

### Alternative Data Sources (Goodreads Backup Plan)
- [ ] StoryGraph CSV import
- [ ] LibraryThing export handler
- [ ] Manual CSV import for any platform
- [ ] Kindle/Audible export parsing
- [ ] Direct ISBN entry with metadata lookup
- [ ] Barcode scanning (future mobile app)

## 📱 PHASE 4: Platform Expansion

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
