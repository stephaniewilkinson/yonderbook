# Yonderbook Authentication Strategy

## Status: POSTPONED - Email Setup Prioritized

**DECISION**: Authentication implementation postponed until email foundation is complete.

**Priority Order**:
1. ✅ Email service setup (SendGrid/Mailgun/SMTP)
2. ✅ Email template system
3. ✅ Basic email sending functionality
4. 🔄 Authentication implementation (this document)
5. 🔄 Database migration

## Previous Strategy (On Hold)

**STRATEGY CHANGE**: All users must create a Rodauth account before using Yonderbook.

This approach ensures:
- ✅ **Data persistence** - No more lost analyses
- ✅ **Legal compliance** - Store user's own Goodreads data permanently
- ✅ **Email notifications** - For library availability and premium features
- ✅ **Clear premium path** - Free tier → Premium tier with auto-checkout

## Why Required Accounts? (Future Implementation)

**Emergency Context**:
- Goodreads API shutting down - must capture data to database
- Legal compliance requires user accounts for permanent data storage
- Session-based system won't survive API shutdown

**User Benefits**:
- Never lose reading analysis again
- Cross-device access to book data
- Email notifications when books become available
- Upgrade path to premium auto-checkout features

## Architecture (Future Implementation)

### Core Components (When Ready)
- **Email Foundation**: Must be complete before implementing
- **Rodauth**: Ruby's most advanced authentication framework
- **Database**: SQLite + Sequel for data persistence
- **Sessions**: Integration with existing session management

### Required Account User Flow (Future)
```
Visit Yonderbook → Create Account (Email/Password) → Verify Email → Connect Goodreads → Analyze Books → Premium Upgrade
```

**Free Tier Features** (When Ready):
- Book analysis and reading insights
- Manual library checking
- BookMooch integration
- Data persistence across devices

**Premium Tier Features ($7/month)** (When Ready):
- Automatic library checkout (OverDrive OAuth)
- Email notifications when books available
- Advanced analytics and trends

## Implementation Plan (POSTPONED)

### Prerequisites
- ✅ Email service configured and working
- ✅ Email templates created
- ✅ Email sending tested in development and production
- 🔄 Database schema ready

### 1. Gem Dependencies (When Ready)

Add to `Gemfile`:
```ruby
# Authentication (AFTER email is working)
gem 'rodauth', '~> 2.40'
gem 'bcrypt'  # For password hashing
gem 'mail'    # For email sending (already configured)

# Database (AFTER email is working)
gem 'sequel'
gem 'sqlite3'
```

### 2. Database Schema for Authentication (POSTPONED)

**NOTE**: Database implementation postponed until email foundation is complete.

See `/planning/database_design.md` for complete schema details when ready to implement.

### 3. Rodauth Configuration (POSTPONED)

**NOTE**: Rodauth configuration postponed until email service is configured and tested.

Previous configuration research completed - ready to implement once email foundation is in place.

## Current Status

**Authentication implementation is POSTPONED until email foundation is complete.**

**Next Steps**:
1. Set up email service (SendGrid/Mailgun/SMTP)
2. Create basic email templates
3. Test email delivery in development
4. Test email delivery in production
5. **THEN** return to authentication implementation

**When Ready**: All configuration and code examples below are ready for implementation once email prerequisite is met.

### 4. Goodreads OAuth Strategy

#### Check if omniauth-goodreads exists
If `omniauth-goodreads` gem doesn't exist, we need to create a custom strategy:

```ruby
# lib/omniauth/strategies/goodreads.rb
require 'omniauth-oauth'

module OmniAuth
  module Strategies
    class Goodreads < OmniAuth::Strategies::OAuth
      option :name, 'goodreads'
      option :client_options, {
        site: 'https://www.goodreads.com',
        request_token_path: '/oauth/request_token',
        access_token_path: '/oauth/access_token',
        authorize_path: '/oauth/authorize'
      }

      uid { raw_info['user']['@id'] }

      info do
        {
          name: raw_info['user']['name'],
          nickname: raw_info['user']['name'],
          email: raw_info['user']['email'], # May not be available
          image: raw_info['user']['image_url'],
          urls: { goodreads: raw_info['user']['link'] }
        }
      end

      extra do
        { raw_info: raw_info }
      end

      private

      def raw_info
        @raw_info ||= begin
          response = access_token.get('/api/auth_user').body
          Hash.from_xml(response)['GoodreadsResponse']
        end
      end
    end
  end
end
```

### 5. Frontend Integration

#### Welcome Page Account Creation (`views/welcome.erb`)
```erb
<div class="hero-section">
  <h1>Never lose track of your reading again</h1>
  <p>Analyze your Goodreads library, find books at your local library, and get automatic checkout notifications.</p>

  <div class="auth-prompt">
    <h2>Get Started</h2>
    <p>Create your account to analyze your reading habits and save your data forever.</p>

    <div class="auth-buttons">
      <a href="/create-account" class="btn btn-primary btn-large">
        Create Free Account
      </a>

      <a href="/login" class="btn btn-secondary">
        Already have an account? Log in
      </a>
    </div>
  </div>
</div>

<div class="features-preview">
  <h3>What you'll get:</h3>
  <ul>
    <li>✅ Analyze your Goodreads reading patterns</li>
    <li>✅ Find books at your local library</li>
    <li>✅ BookMooch trading recommendations</li>
    <li>✅ Save your analysis forever</li>
    <li>⭐ Upgrade to auto-checkout books in Libby ($7/month)</li>
  </ul>
</div>
```

#### Account Status Helper
```ruby
# lib/helpers/auth_helpers.rb
module AuthHelpers
  def require_account_everywhere
    # All features require account
    redirect '/create-account' unless rodauth.logged_in?
    redirect '/verify-account' unless rodauth.verified_account?
  end

  def premium_upgrade_prompt?
    rodauth.logged_in? && !premium_user?
  end

  def show_premium_upgrade?
    # Show after user has used basic features
    session[:analyses_run] && session[:analyses_run] >= 2
  end
end
```

### 6. Environment Configuration

#### `.env` Variables
```bash
# Rodauth
SESSION_SECRET=your-super-secret-session-key-here

# Email configuration for account verification
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=your-sendgrid-api-key
FROM_EMAIL=noreply@yonderbook.com

# Database
DATABASE_URL=sqlite://db/yonderbook.db
```

### 7. Testing Strategy

#### OAuth Flow Testing
```ruby
# spec/auth_spec.rb
RSpec.describe "Authentication Flow" do
  it "creates account from Goodreads OAuth" do
    # Mock Goodreads OAuth response
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:goodreads] = {
      'uid' => '123456',
      'info' => {
        'email' => 'user@example.com',
        'name' => 'Book Reader',
        'image' => 'https://goodreads.com/user.jpg'
      }
    }

    # Test OAuth flow
    visit '/auth/goodreads'

    # Should create account and redirect
    expect(page).to have_current_path('/dashboard')
    expect(User.count).to eq(1)
    expect(Service.where(service_type: 'goodreads').count).to eq(1)
  end
end
```

### 8. Migration Path from Current System

#### For Existing Session Users
```ruby
# lib/auth_migration.rb
class AuthMigration
  def self.link_session_to_account(session_data, account_id)
    # If user had Goodreads data in session, link it to new account
    if session_data['goodreads_user_id']
      user = User.find_by(account_id: account_id)

      # Create service record if it doesn't exist
      unless Service.find(user_id: user.id, service_type: 'goodreads')
        Service.create(
          user_id: user.id,
          service_type: 'goodreads',
          goodreads_user_id: session_data['goodreads_user_id'],
          active: true
        )
      end
    end
  end
end
```

## Next Steps

1. **Install Rodauth gems** (no OAuth dependencies)
2. **Create database migrations** for accounts and users tables
3. **Configure email sending** (SendGrid or similar)
4. **Build account creation flow** with email verification
5. **Require authentication** for all existing features
6. **Build Goodreads connection** flow for verified users
7. **Add premium upgrade** prompts after user engagement

## Required Account Strategy

**Core Authentication**: Email/password with required email verification

**User Journey**:
1. **Visit Yonderbook** → Account creation required
2. **Create Account** → Email/password + verification email
3. **Verify Email** → Access to all basic features
4. **Connect Goodreads** → Manual import of reading data
5. **Use Free Features** → Analysis, BookMouch, library checking
6. **Premium Upgrade** → Auto-checkout + notifications ($7/month)

**Benefits of Required Accounts**:
✅ **Legal compliance** - Can store user's Goodreads data permanently
✅ **Data persistence** - No more lost analyses
✅ **Email communication** - Notifications, updates, premium offers
✅ **Clear business model** - Free tier → Premium tier
✅ **Emergency migration** - Capture all user data before API shutdown

**Free Tier Value**:
- All current Yonderbook functionality
- Permanent data storage
- Cross-device access
- Email notifications for manual library checks

**Premium Tier Value ($7/month)**:
- Automatic OverDrive checkout
- Instant email alerts when books available
- Advanced reading analytics
- Priority customer support