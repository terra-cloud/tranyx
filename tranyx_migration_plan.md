# Tranyx Project Migration Plan: Flutter Mobile + Jaspr Web + ServerPod Server

## Overview
This document outlines the migration strategy for transforming the existing Tranyx Flutter web application into a multi-platform solution with:
- Flutter for mobile (iOS/Android)
- Jaspr for web (replacing current Flutter web implementation)
- ServerPod for server-side Dart implementation (with Riverpod for state management and robust job processing)

## Current State Analysis

### Strengths of Existing Codebase
1. **Well-structured feature modules** - Clear separation of concerns in `lib/features/`
2. **Riverpod adoption** - Extensive use of Riverpod for state management throughout
3. **Firebase integration** - Comprehensive use of Firebase services (Auth, Firestore, Functions, etc.)
4. **Flavor-based configuration** - Proper environment separation (dev/prod)
5. **Internationalization** - Multi-language support already implemented
6. **Web3 foundation** - Partial Web3 auth implementation exists (Phantom wallet, Solana)
7. **Responsive design considerations** - Some responsive widgets already in place

### Areas Requiring Migration
1. **Web layer** - Current Flutter web implementation needs replacement with Jaspr
2. **Platform-specific code** - Need to properly separate mobile/web/platform concerns
3. **State management synchronization** - Ensure Riverpod works consistently across Flutter and Jaspr
4. **Build configuration** - Separate build targets for different platforms
5. **UI/UX adaptation** - Mobile-specific vs web-specific interface considerations

---

## UI/UX Reference Architecture (React → Jaspr)

The target UI is defined by the existing React prototype. The following is the canonical feature and component breakdown to be replicated in Jaspr.

### Account Types
| Type | Badge Color | Description |
|---|---|---|
| `employer` | Blue | Posts jobs, finds freelancers |
| `nyxian` | Green | Finds gigs, offers services (the Tranyx worker identity) |
| `hybrid` | Amber / PRO | Can both hire and work; unlocked via special registration |

### Authentication Flow
1. **Login** – Email + password, forgot password link
2. **Register Path** – Account type selection (Employer / Nyxian / Hybrid PRO)
3. **Register Details** – Full name, email, password
4. **KYC Pending** – Hourglass screen; backoffice review before approval

### Navigation Structure
- **Desktop Sidebar** (≥md): Icon-only vertical nav — Home, Jobs & Gigs, Transit Hub, My Profile + Logout at bottom
- **Mobile Bottom Nav** (<md): Home | Jobs | Transit | Profile with active indicator dot and label
- **App Logo**: Lucide `Hexagon` icon in indigo→purple gradient, label "Tranyx"

### Tab Content Breakdown

#### 🏠 Home Tab
- **Hybrid Switcher**: Segmented toggle — "Find Services" (Employer) / "Work as Nyxian"
- **Hero Header**: Dynamic heading based on mode ("What do you need done?" / "Find your next gig.")
- **Global Search Bar**: Contextual placeholder per mode
- **Ongoing Widget**: 
  - Employer: blue-tinted "Ongoing Job" card with chat shortcut
  - Nyxian: green-tinted "Current Gig" card with live timer and "Complete Gig" button
- **Top Services Grid**: 2×2 (mobile) / 4-col (desktop) category cards from first job group
- **Transit Teaser Card**: Links to Transit tab
- **Real Estate on Chain Teaser**: "V2.0 Coming Soon" waitlist card

#### 💼 Jobs Tab (Master-Detail Layout on Desktop)
**Left pane (list):**
- Employer view: "My Postings" + "Create New Listing" button/dashed card
- Nyxian view: "Available Gigs" with filter chips (Recommended, High Paying)
- `JobCardEmployer`: title, status badge (Active/Reviewing), applicant count, time, Manage button
- `JobCardNyxian`: title, distance, rate, urgency badge, View button

**Right pane (detail):**
- `'list'` state: empty state on desktop ("Select a job to view details")
- `'create'` (3 steps):
  1. Category selector (opens modal) + Job title + AI Auto-Draft description (Gemini) + Employment type + Date type + Time preference
  2. Location type (Onsite/Remote) + Map placeholder + Landmark input
  3. Payment type (daily/weekly/fortnightly/monthly/package) + Amount/rate input
- `'details'`: Job image gallery, rate, distance/urgency/duration chips, description, **Public Q&A section**, action buttons (Employer: Edit + Review Applicants; Nyxian: Proceed to Apply)
- `'review'`: Applicant cards with name, rating, rate, cover note, Accept/Message actions
- `'apply'`: Rate selection (Standard / Counter-offer with custom input) + AI Cover note draft (Gemini)
- `'success'`: Success screen (hired/applied)

#### 🚗 Transit Tab
- Segmented toggle: "Rent a Vehicle" / "Host (My Garage)"
- **Rent view**: Active Rental widget (purple) + search + Vehicle cards (model, type, price, distance)
- **Host view**: Empty CTA card — "Turn your vehicle into earnings" + List a Vehicle button

#### 👤 Profile Tab (Master-Detail Layout on Desktop)
**Left pane (menu):**
- User avatar with gradient ring + name + account type badge
- Menu items: Personal Information, Professional Info / Nyxian Profile, Payment Methods, Trust & Verification, Help & Support
- Logout button (red hover)

**Right pane:**
- `'main'`: Settings overview + prototype account-type switcher buttons
- `'personal'`: Full name, email, phone, address fields + Save button
- `'professional'`: Conditional sections — Nyxian section (headline, rate, skills tags) and/or Employer section (company name, industry, tax ID)
- `'payment'`: Visa card widget + Phantom wallet widget (connect/connected/balance/refresh/disconnect) + Add Payment Method button
- `'trust'`: Verification status header + item list (Government ID, Phone, Email, Background Check)
- `'support'`: Live Chat button + FAQ accordion items

### Category System
16 top-level job groups, each with color + icon + subcategories:

| Group | Color | Example Categories |
|---|---|---|
| Home Repair & Maintenance | amber-600 | Electrician, Plumber, Painter, Locksmith |
| Cleaning & Organizing | indigo-500 | House Cleaning, Laundry, Car Wash |
| Outdoor & Garden | green-600 | Gardener, Pool Cleaning |
| Automotive | sky-500 | Mobile Mechanic, Towing, Oil Change |
| Delivery & Errands | orange-500 | Grocery Delivery, Document Runner |
| Moving & Logistics | blue-600 | Furniture Moving, Packing, Relocation |
| Personal Care & Assistance | pink-500 | Baby Sitter, Pet Grooming, Tutor |
| Tech & IT Support | blue-500 | Software Dev, UI/UX, Blockchain Dev |
| Business, Finance & Admin | emerald-600 | Accountant, HR Manager, Virtual Assistant |
| Creative & Media | purple-500 | Graphic Designer, Video Editor |
| Marketing & Sales | rose-500 | SEO, Social Media Manager |
| Legal, Engineering & Pro | zinc-700 | Lawyer, Civil Engineer, Architect |
| Education & Training | amber-500 | Online Tutor, Corporate Trainer |
| Health & Wellness | red-500 | Health Coach, Physical Therapist |
| Customer Support | blue-500 | Customer Support Rep, Community Mod |
| Miscellaneous & Events | zinc-500 | Event Helper, Survey Taker, Others |

**Category Modal**: Full-screen overlay with search, grouped grid (2–4 cols), animated hover cards.

### AI Features (Gemini Integration)
- **Auto-Draft Job Description**: Triggered from job creation Step 1; uses job title + selected category as context; calls `gemini-2.5-flash` with exponential backoff retry (1s → 16s, max 5 retries)
- **Draft Cover Note**: Triggered from application flow; personalizes the note for counter-offer scenarios
- Both actions show a `Loader2` spinner + "Generating..." label while in-flight

### Crypto Wallet (Phantom / Solana)
- States: `disconnected` → `connecting` (1.2s delay simulation) → `connected`
- Connected state: shows wallet address (truncated), SOL balance with refresh button
- Disconnect button available in connected state
- Phantom brand color: `#AB9FF2`

### Design Tokens
| Token | Value |
|---|---|
| Font | Inter (Google Fonts, weights 400–900) |
| Dark background | `zinc-950` / `zinc-900` |
| Light background | `zinc-50` / `white` |
| Primary accent | `indigo-600` |
| Active gradient | `from-indigo-600 to-purple-500` |
| Border radius | `rounded-2xl`, `rounded-3xl`, `rounded-[2.5rem]` |
| Animation | `fadeUp` keyframe (0.5s cubic-bezier 0.16,1,0.3,1) |
| Scrollbars | Hidden via `.no-scrollbar` utility |

### Reusable Sub-components to Port
| Component | Purpose |
|---|---|
| `SegmentedControl` | Multi-option pill toggle (replaces radio groups) |
| `InputField` | Labeled input with optional leading icon + focus border |
| `SubViewHeader` | Back button + title for nested views (mobile back visible, desktop hidden) |
| `CategoryCard` | Icon + label card used in Home top services |
| `CategoryModal` | Full-screen category browser with search |
| `NavItem` | Mobile bottom nav item with active dot indicator |
| `DesktopNavItem` | Sidebar icon button with active background |
| `LoginCard` | Account-type selection card (icon, title, subtitle, chevron) |
| `JobCardEmployer` | Employer job list card |
| `JobCardNyxian` | Worker gig list card |
| `VehicleCard` | Transit vehicle listing card |
| `ProfileMenuItem` | Profile sidebar menu item |
| `VerificationItem` | Trust & verification status row |
| `SupportFAQ` | FAQ accordion row |
| `Tag` | Skill tag chip |

---

## Migration Strategy

### Phase 1: Project Structure Reorganization

#### 1.1 New Directory Structure
```
tranyx/
├── lib/                    # Shared Dart code (mobile + web + server)
│   ├── core/               # Shared core functionality
│   ├── features/           # Shared feature modules (business logic)
│   ├── models/             # Shared data models
│   ├── services/           # Shared services (Firebase, Gemini, etc.)
│   ├── providers/          # Shared Riverpod providers
│   └── utils/              # Shared utilities
│
├── mobile/                 # Flutter mobile-specific code
│   ├── lib/                # Mobile-specific Flutter implementation
│   ├── android/            # Android-specific configs
│   ├── ios/                # iOS-specific configs
│   └── pubspec.yaml        # Mobile-specific dependencies
│
├── web/                    # Jaspr web-specific code
│   ├── lib/
│   │   ├── client/         # @client components (TranyxApp, all tab views)
│   │   │   ├── widgets/    # All reusable sub-components
│   │   │   └── tranyx_app.dart
│   │   ├── services/       # Firebase REST, Gemini API service
│   │   └── main.server.dart
│   ├── web/
│   │   └── styles.css      # Custom animations, no-scrollbar, global overrides
│   └── pubspec.yaml
│
└── server/                 # ServerPod server implementation
    ├── lib/
    ├── podspec.yaml
    └── pubspec.yaml
```

#### 1.2 Shared Code Identification
Extract truly platform-independent code to `lib/`:
- Business logic (job posting, application flow, user profile)
- Data models (`JobModel`, `UserModel`, `ApplicationModel`, `VehicleModel`)
- Firebase service wrappers (auth, Firestore CRUD)
- Gemini API service (shared prompt templates, retry logic)
- Riverpod providers (where applicable)
- Job category constants (`JOB_GROUPS` equivalent as Dart enums/lists)

### Phase 2: Mobile Implementation (Flutter)

#### 2.1 Mobile-Specific Adaptations
- **Navigation**: Bottom tab bar mirroring the web's 4 tabs (Home, Jobs, Transit, Profile)
- **UI Components**: Adapt existing widgets for mobile touch targets
- **Platform Plugins**:
  - Camera, geolocation, file picker (mobile-optimized)
  - `solana_wallets_flutter` for Phantom wallet integration
  - FCM for push notifications
- **Performance**: Optimize for mobile constraints

#### 2.2 Firebase Configuration
- Maintain existing flavor-based Firebase configuration
- Ensure `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are properly configured
- Keep dev/prod Firebase project separation

#### 2.3 Dependencies
```yaml
dependencies:
  flutter_launcher_icons: ^0.14.4
  flutter_native_splash: ^2.4.0
  solana_wallets_flutter: latest
  walletconnect_flutter_v2: latest
```

### Phase 3: Web Implementation (Jaspr)

#### 3.1 Jaspr Project Setup
- Jaspr project in `packages/tranyx_web/`
- `@client` annotation on `TranyxApp` and all interactive components
- Firebase REST API service (no JS SDK dependency)
- Tailwind CSS via CDN + custom `web/styles.css`
- Lucide icons via CDN with `MutationObserver` initialization pattern

#### 3.2 State Management
The React `useState` hooks map directly to Jaspr `StatefulComponent` state fields:

| React State | Jaspr Equivalent |
|---|---|
| `isDarkMode` | `bool isDarkMode` in `TranyxAppState` |
| `isAuthenticated` | `bool isAuthenticated` |
| `accountType` | `String accountType` ('employer'/'nyxian'/'hybrid') |
| `activeTab` | `String activeTab` |
| `jobsView` | `String jobsView` |
| `profileView` | `String profileView` |
| `walletState` | `String walletState` |
| `jobQuestions` | `List<JobQuestion> jobQuestions` |

#### 3.3 Component Architecture
Each React subcomponent becomes a Jaspr `StatelessComponent` or `StatefulComponent`:
- Pass `isDarkMode` and callback functions as constructor parameters
- Use `css()` classes to apply Tailwind utility classes
- Conditional rendering replaces React's `&&` / ternary patterns

#### 3.4 Gemini Integration in Jaspr
- Implement `GeminiService` in `lib/services/gemini_service.dart`
- Uses `http.Client` (cross-platform compatible)
- Exponential backoff: delays `[1, 2, 4, 8, 16]` seconds, max 5 retries
- Prompt templates for: job description auto-draft, cover note drafting

#### 3.5 Firebase Integration in Jaspr
- Use Firebase Auth REST API (`identitytoolkit.googleapis.com`)
- Use Firestore REST API (`firestore.googleapis.com`)
- Conditional imports (`dart:html` stub for server, real impl for browser)
- `SessionStorage` wrapped in browser-guard for SSR safety

### Phase 4: ServerPod Considerations

#### 4.1 ServerPod Overview
ServerPod is a scalable server framework for Dart/Flutter applications:
- Automatic code generation for client-server communication
- Built-in support for authentication, sessions, and caching
- Database integration with PostgreSQL
- Background job processing capabilities

#### 4.2 Evaluation of Need
Evaluate which Firebase Functions should move to ServerPod:
- Benefits: More control, automatic Dart client generation, integrated auth/sessions
- Drawbacks: Additional DevOps overhead, learning curve

#### 4.3 ServerPod Implementation Approach
Use ServerPod for:
- Complex business logic requiring transactions
- Third-party API integrations
- Webhook handlers
- Background jobs and scheduled tasks (stale job monitoring, notification processing, payment webhooks)
- API endpoints serving both mobile and web clients

Maintain Firebase for:
- Authentication (optional migration)
- Firestore (real-time capabilities)
- Cloud Storage
- Hosting

#### 4.4 Jobs and Job Groups with ServerPod
- **Stale Job Monitoring**: Migrate `StaleJobService` to ServerPod background jobs
- **Notification Processing**: Offload FCM notification sending
- **Payment Processing**: Handle payment webhooks and verification
- **Data Synchronization**: Sync data between Firestore and PostgreSQL
- **Report Generation**: Async report generation
- **File Processing**: Image processing, virus scanning

### Phase 5: Web3 Authentication Migration

#### 5.1 Shared Web3 Service
- Abstract wallet connection logic
- Chain-specific implementations (EVM/Solana)
- Nonce management and signature verification

#### 5.2 Platform-Specific Implementations
- **Mobile**: `solana_wallets_flutter` + `walletconnect_flutter_v2`
- **Web (Jaspr)**: JS interop for Phantom browser extension; wallet connect button in Payment Methods profile tab
- **Server**: Verification logic via ServerPod endpoints

#### 5.3 Phantom Wallet UI States (Web)
```
disconnected → [Connect Phantom button, #AB9FF2 brand color]
connecting   → [Loader2 spinner, "Connecting..." label, 1.2s simulated delay]
connected    → [Wallet address (truncated), SOL balance, RefreshCw button, LogOut disconnect]
```

### Phase 6: Implementation Roadmap

#### Sprint 1: Foundation (Weeks 1-2)
- [ ] Finalize Jaspr project structure in `packages/tranyx_web/`
- [ ] Port all 16 job group category definitions to Dart constants
- [ ] Implement `TranyxAppState` with all state fields
- [ ] Build `Document` with Tailwind CDN, Lucide CDN, Google Fonts, custom CSS
- [ ] Implement `AuthFlow` component (Login, Register Path, Register Details, KYC Pending)

#### Sprint 2: Core Navigation & Home (Weeks 3-4)
- [ ] Implement `DesktopSidebar` and `MobileBottomNav`
- [ ] Implement `TopHeader` (logo, mode badge, dark/light toggle, notifications)
- [ ] Build `HomeTab` (hero, search, ongoing widget, services grid, teasers)
- [ ] Implement `CategoryCard` and `CategoryModal` with search filter
- [ ] Implement Hybrid account mode switcher

#### Sprint 3: Jobs & Transit Tabs (Weeks 5-6)
- [ ] Build `JobsTab` master-detail layout
- [ ] Port all job sub-views: `create` (3 steps), `details`, `review`, `apply`, `success`
- [ ] Implement Public Q&A section with reply functionality
- [ ] Integrate `GeminiService` for auto-draft description and cover note
- [ ] Build `TransitTab` with rent/host toggle and vehicle cards

#### Sprint 4: Profile Tab & Wallet (Weeks 7-8)
- [ ] Build `ProfileTab` master-detail layout
- [ ] Implement all profile sub-views: personal, professional, payment, trust, support
- [ ] Implement Phantom wallet connection widget with all three states
- [ ] Implement `SegmentedControl`, `InputField`, `Tag` reusable components

#### Sprint 5: Auth Backend & Firebase (Weeks 9-10)
- [ ] Connect Login/Register to Firebase Auth REST API
- [ ] Connect job posting to Firestore REST API
- [ ] Connect user profile reads/writes to Firestore
- [ ] Implement KYC status check on app load
- [ ] Verify SSR hydration (server renders shell, client takes over)

#### Sprint 6: Mobile Flutter Parity (Weeks 11-12)
- [ ] Implement auth flow for mobile
- [ ] Implement Home, Jobs, Transit, Profile tabs for mobile
- [ ] Integrate Phantom wallet via native SDK
- [ ] FCM push notifications
- [ ] Cross-platform testing

#### Sprint 7: ServerPod & Web3 Completion (Weeks 13-14)
- [ ] Set up ServerPod project and configure PostgreSQL
- [ ] Migrate Firebase Functions to ServerPod (starting with Web3 auth verification)
- [ ] Implement background job system (stale jobs, notifications, payments)
- [ ] Complete Web3 auth flows on mobile and web
- [ ] Final security review and release candidates

---

## Risk Mitigation

### Technical Risks
1. **Jaspr SSR + @client hydration** — Test all stateful interactions early; use `@client` annotation on any component that needs browser APIs
2. **Firebase REST API limitations** — Thoroughly test Firestore query pagination; consider caching layer
3. **Gemini API rate limits** — Exponential backoff already designed in; add user-facing error states
4. **Lucide icons in Jaspr** — Use `MutationObserver` pattern (already implemented) to re-initialize icons after DOM mutations
5. **Phantom wallet browser interop** — Use conditional imports to guard `dart:js_interop` calls from server context
6. **State Management Inconsistency** — Normalize all state to `TranyxAppState`; avoid prop drilling beyond 2 levels

### Schedule Risks
1. **Underestimating component count** — There are 20+ sub-components; allocate separate sprints per tab
2. **Firebase Configuration Complexity** — Maintain existing working configuration; test early and often
3. **Responsive breakpoint parity** — Web uses `md:` breakpoints for sidebar/master-detail; test on both viewport sizes

---

## Success Criteria

### Functional Parity
- All 4 tabs (Home, Jobs, Transit, Profile) render correctly in dark and light mode
- Authentication flow (Login → Register → KYC → Dashboard) works end-to-end
- Job creation (3-step form), application (cover note + counter-offer), and acceptance flow all function
- Gemini AI auto-draft works for both job descriptions and cover notes
- Phantom wallet connect/disconnect/balance-refresh works in browser
- All 16 job category groups and their subcategories are browsable in the category modal
- Mobile bottom nav and desktop sidebar both function correctly at their respective breakpoints

### Technical Excellence
- Maximum code sharing without compromising platform-specific optimizations
- Clean separation of concerns (server entry, client components, services)
- Maintainable and testable codebase
- Proper error handling (API failures, wallet errors, auth errors)

### Performance Benchmarks
- Mobile: <2s startup time, smooth 60fps animations
- Web: <3s first contentful paint, `fadeUp` animations at 0.5s cubic-bezier
- Gemini API: retry logic handles transient failures without user frustration
- Server: Efficient job processing with minimal latency

---

## Open Questions

1. **KYC integration** — Is KYC handled by a third-party service (Persona, Onfido) or internally?
2. **Real-time chat** — The Q&A section currently shows mock data; will this use Firestore real-time listeners or a separate chat service?
3. **Crypto payments** — Are Tranyx job payments processed on-chain (SOL), or is crypto only used for wallet identity linking?
4. **Transit module** — Is vehicle listing a real Firestore collection, or deferred to a later phase?
5. **Nyxian identity** — Are "Nyxian" accounts a Firestore user type field, or managed via Firebase custom claims?

---

## Next Steps

1. Review and approve this refined migration plan
2. Confirm open questions above before Sprint 3
3. Begin implementation following the outlined roadmap
4. Regular check-ins to ensure alignment and adjust plan as needed

---
*Migration plan created: 2026-05-15*  
*Renamed from Terra → Tranyx: 2026-05-15*  
*Target completion: 2026-08-15 (approximately 14 weeks)*
