# Yonderbook Implementation Plan

**Status**: Research complete, email implementation prioritized
**Last Updated**: September 25, 2024

## 🎯 Project Vision
Transform Yonderbook into a premium book automation service with the killer feature: **"Add to TBR anywhere → Book appears in Libby automatically"**

**Current State:**
- 586 active users (last 12 months)
- Works without accounts (session-based)
- Goodreads OAuth broken for new users (API deprecated)
- No database (stateless cache system)

## 🚨 Critical Context

### Goodreads API Crisis
- **DEPRECATED**: Developer portal inaccessible, can't modify OAuth settings
- **Broken OAuth**: New users get stuck on Goodreads, won't redirect back
- **Emergency Timeline**: API could shut down completely at any time
- **Workaround**: Manual instructions added to welcome page

### Legal Compliance (Goodreads ToS)
**What we CAN store:**
✅ User's own OAuth-authenticated Goodreads data (permanent storage)
✅ Book metadata from other APIs (Google Books, Open Library)
✅ User profile info from OAuth (email, name, avatar)

**What we CANNOT store:**
❌ Bulk Goodreads catalog data (24-hour limit)
❌ Other users' reviews without OAuth consent
❌ Non-authenticated public data permanently

## 💰 Business Model: Freemium SaaS

**Free Tier:**
- Current functionality (book analysis, BookMooch, library checking)
- Session-based, no account needed
- Manual library checking

**Premium Tier ($7/month):**
- **Killer Feature**: Automatic checkout in OverDrive/Libby
- Email notifications when books available
- Persistent data across devices
- Advanced analytics

**Revenue Target:** 5-10% conversion = 30-60 premium subscribers = $210-420/month

## 🏗️ Technical Architecture

**UPDATED PRIORITY**: Email implementation first, then authentication and database.

### ~~Authentication Strategy~~ (Postponed)
~~Rodauth core with OAuth providers - postponed until email is working~~

### ~~Database Strategy~~ (Postponed)
~~SQLite + Sequel ORM - postponed until email is working~~

### Email Strategy (PRIORITY #1)
**Options:**
- SendGrid (100 emails/day free)
- Mailgun (5,000 emails/month free)
- SMTP (Gmail, etc.)
- Development: Console logging

**Required For:**
- Account verification
- Password recovery
- Premium notifications
- Business communication

## 🛠️ Implementation Stack

### Core Technologies
- **Framework**: Roda (existing)
- **Email**: TBD (Priority #1)
- **Database**: ~~SQLite + Sequel ORM~~ (Postponed)
- **Authentication**: ~~Rodauth~~ (Postponed)
- **Background Jobs**: TBD
- **Payments**: Stripe (Phase 2)

## 📅 REVISED Implementation Phases

### 🚨 Phase 1: Email Foundation (Week 1)
**Priority:** Set up reliable email delivery

1. **Email Service Setup**
   - Choose and configure email provider
   - Test email delivery in development
   - Create email templates
   - Environment configuration

2. **Email Integration**
   - Basic email sending functionality
   - Template system
   - Error handling and logging

### 💰 Phase 2: Authentication (Week 2)
**Priority:** User accounts with email verification

1. **Simple Authentication**
   - Basic login/signup forms
   - Email verification flow
   - Session management
   - Password recovery

### 🚀 Phase 3: Database & Features (Weeks 3-4)
**Priority:** Data persistence and premium features

1. **Database Migration**
   - SQLite + Sequel setup
   - Data migration from sessions
   - User and book data storage

2. **Premium Features**
   - OverDrive OAuth integration
   - Auto-checkout system
   - Email notifications

## 🔧 Next Immediate Actions

1. **Research email providers** (SendGrid vs Mailgun vs SMTP)
2. **Set up development email** (console logging)
3. **Create basic email templates**
4. **Test email sending** before building on top

## 🎯 Success Metrics

**Phase 1 Success:**
- Email delivery working in development and production
- Templates created and tested
- Foundation ready for authentication

**Long-term Success:**
- All 586 users can continue using service
- Email-based account system working
- Premium tier ready for launch

---

**Status**: Email setup prioritized, database and auth postponed. Starting with solid foundation. 🚀