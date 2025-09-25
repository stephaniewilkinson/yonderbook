# Yonderbook Database Schema Design

## Implementation Phases

### Phase 1: Store Current Data (Emergency)
**Goal**: Capture existing Goodreads/BookMooch data before API shutdown
- Users table (via Rodauth)
- Services table (Goodreads OAuth, BookMooch credentials)
- Books table (on-demand, lazy loading)
- User_books table (current shelf data)

### Phase 2: Premium Features & Expansion
**Goal**: Add premium auto-checkout and additional integrations
- OverDrive OAuth fields in services table
- Auto-checkout fields in user_books table
- Library systems and availability tracking
- Subscription management

## Architecture Overview

### Authentication: Rodauth
- Email-only authentication with account verification
- Premium tier gating via verified emails
- Built-in security (sessions, rate limiting)

### Data Strategy
- **Books**: On-demand storage with ISBN-13 deduplication
- **ISBN Challenge**: Goodreads may not provide ISBN-13, requiring API lookup
- **Lazy loading**: Only fetch/store book metadata when first encountered
- **Email Strategy**: Capture emails from Goodreads OAuth, sync with Rodauth accounts for notifications

### Legal Compliance: Goodreads API Terms of Service

**Data Storage Restrictions:**
- **24-hour limit** on cached Goodreads API data (general/public data)
- **Exception**: User's own OAuth-authenticated data can be stored permanently
- **No bulk harvesting** without explicit written consent from Goodreads
- **No redistribution** of Goodreads data to third parties

**What Yonderbook CAN store:**
✅ **User's own book data** from their authenticated Goodreads account (shelves, ratings, reviews)
✅ **Book metadata** for books the user has interacted with via OAuth
✅ **User profile info** shared via OAuth (email, name, avatar)
✅ **ISBN-based book metadata** from other sources (Google Books, Open Library)

**What Yonderbook CANNOT store:**
❌ Bulk Goodreads catalog data beyond 24 hours
❌ Other users' reviews/data without their OAuth consent
❌ Non-authenticated public Goodreads data permanently

**Implementation Strategy:**
- Store user's OAuth-authenticated Goodreads data permanently (compliant)
- Cache general book metadata briefly (24 hours) then expire
- Primary book metadata from Google Books/Open Library APIs (no restrictions)
- Explicit user consent required for any data modifications

## Phase 1 Schema: Current Data Capture

### Rodauth Authentication Tables

Rodauth will automatically create and manage these tables:

#### `accounts` - Rodauth's user accounts
- `id` (primary key, auto-increment)
- `email` (unique, not null)
- `status_id` (integer, default 1: unverified=1, verified=2, closed=3)
- `created_at`, `updated_at` (timestamps)

#### `account_statuses` - Account verification states
- `id` (primary key)
- `name` (unique, not null)
- Pre-populated with: Unverified, Verified, Closed

#### `account_verification_keys` - Email verification tokens
- `id` (primary key, auto-increment)
- `account_id` (unique, foreign key to accounts)
- `key` (unique verification token)
- `requested_at`, `expires_at` (timestamps)

### Yonderbook Application Tables

#### `users` - User profiles
- `id` (primary key, auto-increment)
- `account_id` (unique, foreign key to Rodauth accounts)
- `goodreads_profile_image_url` (string, from Goodreads OAuth)
- `display_name` (string, from Goodreads profile or email)
- `created_at`, `updated_at` (timestamps)

#### `services` - Phase 1: Goodreads & BookMooch only
- `id` (primary key, auto-increment)
- `user_id` (foreign key to users)
- `service_type` (string: 'goodreads', 'bookmooch')
- **Goodreads OAuth 1.0:**
  - `goodreads_user_id`
  - `goodreads_token`
  - `goodreads_secret`
  - `goodreads_username` (display name from profile)
  - `goodreads_email` (email address from OAuth)
  - `goodreads_profile_url` (link to their Goodreads profile)
- **BookMooch Basic Auth:**
  - `bookmooch_username`
  - `bookmooch_password_encrypted`
- `active` (boolean, default true)
- `last_sync_at` (timestamp)
- `created_at`, `updated_at` (timestamps)
- **Constraints:** Unique(user_id, service_type)
- **Indexes:** user_id + active

#### `books` - On-demand book metadata
- `isbn` (primary key, varchar 20 - ISBN-13 preferred, ISBN-10 if that's all we have)
- `isbn_10` (varchar 10, for backward compatibility)
- `isbn_13` (varchar 13, store separately since Goodreads may not provide)
- `title` (string, required)
- `authors` (JSON array of author names)
- `published_year` (integer)
- `cover_image_url` (string)
- `goodreads_id` (string, for cross-referencing)
- `metadata_source` (string: 'goodreads', 'google_books', 'open_library')
- `metadata_updated_at` (timestamp)
- `first_seen_at` (timestamp)
- `created_at`, `updated_at` (timestamps)
- **Constraints:** Unique constraints on isbn, isbn_10, isbn_13
- **Indexes:** title, goodreads_id, unique indexes on isbn fields

#### `user_books` - Phase 1: Goodreads & BookMooch data
- `id` (primary key, auto-increment)
- `user_id` (foreign key to users)
- `service_id` (foreign key to services)
- `book_isbn` (foreign key to books.isbn)
- **Goodreads-specific data:**
  - `shelf_name` (string: 'to-read', 'read', 'currently-reading')
  - `goodreads_rating` (integer 1-5)
  - `goodreads_review` (text)
  - `goodreads_date_read` (date)
  - `goodreads_date_added` (date)
- **BookMooch-specific data:**
  - `on_bookmooch_wishlist` (boolean, default false)
  - `bookmooch_added_at` (timestamp)
- **Service metadata:**
  - `service_book_id` (string, book ID in external service)
  - `service_metadata` (JSON, raw service data)
- `created_at`, `updated_at` (timestamps)
- **Constraints:** Unique(user_id, service_id, book_isbn)
- **Indexes:** user_id + shelf_name, service_id + updated_at

## Phase 2 Schema: Premium Features (Future)

### Additional Fields for `users` table
- `subscription_tier` (string, default 'free')
- `subscription_status` (string)
- `stripe_customer_id` (string)
- `premium_expires_at` (timestamp)

### Additional Fields for `services` table
**OverDrive OAuth 2.0 fields:**
- `overdrive_user_id`
- `overdrive_access_token`
- `overdrive_refresh_token`
- `overdrive_token_expires_at`
- `overdrive_library_id`

### Additional Fields for `user_books` table
**Auto-checkout fields:**
- `auto_checkout_enabled` (boolean, default false)
- `last_checkout_attempt` (timestamp)
- `checkout_status` (string: 'available', 'checked_out', 'on_hold', 'unavailable')

## ISBN Handling Strategy

**Challenge**: Goodreads may not provide ISBN-13
**Solution**: Multi-step ISBN resolution

1. Try to get clean ISBN from Goodreads data first
2. If we only have ISBN-10, convert to ISBN-13
3. If still no ISBN-13, try external APIs (Google Books, Open Library)
4. Use best available ISBN as primary key

## Book Metadata Strategy

**API Priority Chain:**
1. Local books table lookup
2. Google Books API (if ISBN available)
3. Open Library API (fallback)
4. Store minimal data if no APIs work

## Next Steps

**Phase 1 (Emergency - Weeks 1-2):**
1. Create database migrations for compliant data storage
2. Implement book metadata service (Google Books/Open Library primary)
3. Build OAuth-authenticated Goodreads data capture (legal permanent storage)
4. Implement 24-hour expiry for non-user-specific cached data
5. Migrate existing cache data with legal compliance

**Phase 2 (Weeks 3+):**
5. Add premium subscription fields via Sequel migrations
6. Implement OverDrive OAuth for auto-checkout
7. Build auto-checkout background job system
8. Add email notification system