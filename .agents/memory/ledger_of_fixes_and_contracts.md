# Tranyx Workspace Memory: Ledger of Fixes & Invariants

This memory document acts as an immutable ledger to prevent regressions across `tranyx_web`, `tranyx_mobile`, and `shared`.

---

## 1. User Profile Hydration, Authentication & Strict Fallback Ban (VERIFIED & CONFIRMED)
* **Rules**:
  - **Strict No-Overwrite Ban on Sign-In**:
    - `handleSignIn` must **NEVER** call `saveUser()` on login. Sign-in only queries/reads the existing Firestore document (`users/{uid}`). If a fetch returns null or is delayed, calling `saveUser()` will overwrite the user's entire profile document with empty defaults and wipe out all custom fields (photo, phone, headline, skills, rate, tax ID).
    - In `handleSignIn`, `loadUserProfile`, and `_restoreSession`, implement a retry mechanism (3 attempts with 250ms backoff) to account for auth token propagation and avoid temporary network drops.
  - **Photo URL Isolation & Session Clearance**:
    - `_pho` (`tranyx_photo_url`) must be explicitly removed from `localStorage` on `SessionStorage.clear()`.
    - In `SessionStorage.save()` and `SessionStorage.saveProfile()`, if `photoUrl` is null or empty, `_pho` must be removed from `localStorage` to prevent leaking or persisting an avatar from a previously logged-in user.
    - In `handleSignIn`, `userPhotoUrl = profile.photoUrl` must strictly bind to the authenticated user's profile and never fall back to stale in-memory or localStorage values from prior accounts.
  - **Custom Image Upload Parsing & Persistence**:
    - [`readFilesFromEvent`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/services/web_interop_browser.dart) uses dynamic event inspections across `web.HTMLInputElement`, `web.Event`, and `JSObject` targets to ensure DOM change events from hidden `<input type="file">` elements read raw image bytes across all browser engines without throwing `CastError`.
    - [`ImgBBService.uploadImageBytes`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/services/firebase_service.dart) implements dual transport (URL-encoded base64 POST followed by multipart request fallback) to avoid browser CORS/streaming upload failures.
    - [`handleProfilePhotoUpload`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart) saves the generated URL to Cloud Firestore (`users/{uid}`), updates `SessionStorage`, updates component state (`userPhotoUrl`), and displays toast notifications upon success or error.
  - **Automatic Auth Email Defaulting**:
    - `initializeProfileEditing()` and `_PersonalInfo.build` automatically populate `editEmail` with the authenticated session email (`userEmail` or `SessionStorage.email`) whenever `profile.email` is absent or uninitialized.
    - `editName` automatically falls back to `userName` / `SessionStorage.displayName` when `profile.name` is empty or `'User'`.
  - **No Fake / Synthetic Fallback Profiles**: Never construct fake user profiles (e.g. `name: 'User'`, `'Alex Mercer'`, `accountType: employer`) to masquerade as an authenticated session when Firestore returns no user document.
  - **Resilient Firestore Model Decoding**:
    - In [`UserProfile.fromMap`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/shared/lib/src/models.dart), support resilient aliases:
      - `name`: `map['name']` -> `map['displayName']` -> `map['email'].split('@').first`
      - `photoUrl`: `map['photoUrl']` -> `map['avatarUrl']` -> `map['picture']`
      - `phoneNumber`: `map['phoneNumber']` -> `map['phone']` -> `map['contactNumber']`
      - `taxId`: `map['taxId']` -> `map['tin']`
      - `headline`: `map['headline']` -> `map['bio']` -> `map['title']`
      - `businessName`: `map['businessName']` -> `map['companyName']`
  - **Self-Healing Profile Subview Initialization**:
    - In [`_PersonalInfo.build`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/profile_view.dart) and [`_ProfessionalInfo.build`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/profile_view.dart), include self-healing checks so that edit form variables immediately populate from the loaded profile and authenticated session.
  - **DOM Input Attribute Binding**: In [`inputField`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/components/ui_helpers.dart), include `'value': value` in the HTML DOM attributes to ensure Jaspr virtual DOM reconciliation synchronizes input values correctly across re-renders.
  - **Unauthenticated / Missing User Profile Handling**:
    - **Web**: In [`loadUserProfile`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart) and [`_restoreSession`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart), if `uid == null` or the Firestore user doc is `null`, execute `SessionStorage.clear()`, set `isAuthenticated = false`, `userProfile = null`, and set `authView = AuthView.login` so the login popup/modal is immediately presented.
    - **Mobile**: In [`userProfileProvider`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile/lib/features/auth/providers/auth_provider.dart), if `!doc.exists || doc.data() == null`, return `null`. [`MainWrapper`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile/lib/features/navigation/presentation/main_wrapper.dart) will route to `RegisterCompleteProfileView` or show the `AuthView` login screen.
  - **Profile Input State Binding**: In [`_PersonalInfo`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/profile_view.dart) and [`_ProfessionalInfo`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/profile_view.dart), all input fields (`editName`, `editEmail`, `editPhone`, `editTaxId`, `editHeadline`, `editHourlyRate`, `editBusinessName`, `editIndustry`, `editSkills`) bind directly to their state variables without empty fallback ternaries to prevent keystroke reversion during editing.
  - **ImgBB Image Upload & Firestore Persistence**:
    - `ImgBBService` in [`firebase_service.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/services/firebase_service.dart) prioritizes `Env.imgbbApiKey` directly to avoid unnecessary 404 GET requests to non-existent `config/app_config` documents.
    - [`handleProfilePhotoUpload`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart) uploads image bytes to ImgBB and immediately persists `photoUrl` to Cloud Firestore (`users/{uid}`) via `setDocument` and `saveUser`, and stores `photoUrl` in `SessionStorage` (`tranyx_photo_url`).
    - Custom image uploads are accessible both via the camera button on the sidebar avatar (`_ProfileMenu`) and the "Change Photo" card in `_PersonalInfo`.
  - **Google Profile Synchronization**: In [`handleGoogleSignIn`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart) and [`_checkGoogleRedirectResult`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart), when `authResult.photoUrl` and `authResult.displayName` exist, update the Firestore user doc if `photoUrl` was previously null or `name` was `'User'`. In `loadUserProfile()` and `_restoreSession()`, never overwrite `userPhotoUrl` with `null`.
  - **Firestore Security Rules**: In [`firestore.rules`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/firestore.rules), regular authenticated users must be permitted to update their own profile document (`name`, `email`, `phoneNumber`, `photoUrl`, `headline`, `skills`, `hourlyRate`, `businessName`, `industry`, `taxId`, `verificationLevel`, etc.) without being blocked on `affectedKeys().hasAny` checks. Only administrative keys (`role`, `banned`, `suspendedUntil`) are protected from user modification.
  - **Firestore REST Serialization**: [`_fromFirestoreDoc`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/services/firebase_service.dart) in `firebase_service.dart` decodes `timestampValue`, `referenceValue`, and `geoPointValue` correctly.
  - **Refresh Token Persistence**: In [`SessionStorage.save`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/services/web_interop_browser.dart), the `refreshToken` (`tranyx_refresh`) must always be preserved in `localStorage` to allow seamless silent token refreshes across session reloads.

---

## 2. Gemini AI Auto-Drafting, Support & Generative Engine (VERIFIED & CONFIRMED)
* **Rules**:
  - **Self-Healing Gemini Initialization**:
    - In [`generateJobDesc`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart) and [`generateCoverNote`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/tranyx_app.dart), check `if (_gemini == null) _initGemini();` before attempting AI generation.
  - **Textarea Value & Virtual DOM Synchronization**:
    - In [`jobs_view.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/jobs_view.dart) and [`post_job.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/pages/post_job.dart), `<textarea>` elements must include `'value': s.newJobDesc` / `'value': s.coverNote` in their `attributes` map as well as child text `[Component.text(...)]` to ensure auto-drafted text updates the browser DOM `.value` properly upon state re-renders.
  - **Gemini Model Routing & Multilingual Capabilities**:
    - [`TranyxAIService`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/shared/lib/src/ai_service.dart) targets `gemini-3.6-flash` (primary) and `gemini-flash-latest` (fallback).
    - Auto-drafting automatically detects the input language and writes descriptions/cover notes in English, Tagalog (Filipino), or Waray-Waray according to context.

---

## 3. Treasury Vault, Payment Methods & On-Chain Settlement (VERIFIED & CONFIRMED)
* **Rules**:
  - **Payment Methods View**: In [`packages/tranyx_web/lib/client/views/profile_view.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/profile_view.dart), the Phantom Wallet card is removed from the Payment Methods section.
  - **Top-Up & Subscriptions**: Platform target Solana address must always use `Env.solanaPublicKey` (Treasury Vault address) and never hardcoded test addresses (`4zMMC...`).
  - **Withdrawals (Cash-Out)**:
    - **Web**: `broadcastTreasuryTransfer` (SOL) and `broadcastTreasuryTokenTransfer` (USDT) execute direct on-chain transfers from `Env.solanaPrivateKey` via `@solana/web3.js` to the user's destination `walletPublicKey`.
    - **Mobile**: `signAndBroadcastTransfer` (SOL) and `signAndBroadcastTokenTransfer` (USDT) in `phantom_provider.dart` sign with `Env.solanaPrivateKey` via `pinenacl` Ed25519 and broadcast directly to Solana RPC.
    - Transaction signatures (`solanaTxSignature`) must be recorded in both `transactions` and `withdrawalRequests` collections with status `'Successful'` / `'Completed'`.

---

## 4. Web & Mobile Security (VERIFIED & CONFIRMED)
* **Rules**:
  - CI/CD GitHub workflows must use 40-character immutable commit SHAs for third-party actions.
  - Mobile manifest must retain `android:networkSecurityConfig="@xml/network_security_config"` and `android:allowBackup="false"`.

---

## 5. Job Cancellation Integrity & Lockout Matrix (VERIFIED & CONFIRMED)
* **Rules**:
  - **Unilateral Cancellation Lockout Once Hired**:
    - If `job.isHired` (or `acceptedNyxianId` is set / status is `IN_PROGRESS`, `NYXIAN_ACCEPTED`, `COMMITTED`, `UNDER_REVIEW`), unilateral employer cancellation is strictly forbidden (`JOB_ALREADY_COMMITTED`).
    - UI hides or disables unilateral cancel buttons and presents `_buildProtectedHireBanner` / "Cancellation Locked" with Admin/Support Dispute instructions.
  - **Open Job Cancellation**:
    - An open job (`OPEN` / `PUBLISHED` with no accepted Nyxian) may be cancelled with 100% escrow refund.
    - All pending applications are updated in batch to status `REJECTED_JOB_CANCELLED`.
    - Cancellation audit events are logged to the `/job_cancellation_logs` collection.
  - **Terminal / Completed State Transition Guards**:
    - Completed or terminal jobs (`COMPLETED`, `CANCELLED`, `ADMIN_CANCELLED`) cannot be cancelled or applied to (`INVALID_STATE_TRANSITION` / `JOB_IS_TERMINAL`).
  - **Admin Override Cancellation**:
    - Admins can override cancellation with a required reason ($\ge 20$ characters), releasing escrow and logging to audit logs.

---

## 6. AI Auto-Draft Generator, Category Tuning & Profanity Moderation [LOCKED - VERIFIED & COMPLETED - DO NOT MODIFY]
* **Status**: **LOCKED & ENFORCED** (Complies with AC-DRAFT-01 through AC-DRAFT-07, tested and verified across `shared`, `tranyx_mobile`, and `tranyx_web`).
* **Rules**:
  - **Category-Specific Prompt Tuning**:
    - `generateJobDescription` receives `categoryLabel` and adapts prompts and fallbacks for vehicle rental, courier/delivery, home repair, etc., ensuring specific logistics/tool terms are generated.
  - **Category Mismatch Validation & Rejection Invariant**:
    - If the input job title does not reasonably align with the selected category (e.g. plumbing title under Vehicle Rental or driver title under Plumbing), `generateJobDescription` strictly throws `CategoryMismatchException` (`isCategoryMismatch`).
    - The client UI (Mobile snackbar / Web alert toast) displays the mismatch warning directly to the user to prevent generating misaligned garbage.
  - **Multilingual Auto-Drafting (English, Tagalog, Waray-Waray)**:
    - Auto-Draft detects the language of the prompt/title (`detectLanguage`). When aligned with the category, it drafts the job description in fluent **Tagalog** or **Waray-Waray** if the prompt was provided in those regional languages.
  - **Rich Category Description Invariant (No Raw Title Quoting / Generalizing)**:
    - Auto-Drafting synthesizes rich descriptions outlining specific tasks, tools, materials, and safety measures (`getCategorySpecificDraft`) instead of simply wrapping the input title in quotes (`para hit "..."`).
  - **Profanity Moderation Word-Boundary Invariant**:
    - `checkProfanity` in `shared` and `tranyx_web` must use word boundaries (`RegExp(r'(^|[^\w])' + RegExp.escape(phrase) + r'([^\w]|$)')`) so common words with clean substrings ("assistance", "fast pass", "kanto", "paspas", "kikiam") are NEVER falsely flagged.
  - **Explicit Draft Preview & Confirmation Workflow**:
    - Auto-Draft generator opens an explicit preview sheet / modal (`_AIDraftPreviewSheet` on Mobile, `s.showAIDraftModal` on Web).
    - **Discard**: Closes the preview and leaves the description field untouched (zero overwrite).
    - **Use This Draft**: Populates and replaces the description field with the generated/edited text.

---

## 7. Vehicle Rental Driver License Requirement (With Driver vs Self-Drive) [VERIFIED & ENFORCED]
* **Rules**:
  - **With Driver (Chauffeur-Driven) Flow**:
    - When `hireWithDriver == true` (`WITH_DRIVER`), the Driver's License Number field is completely omitted/hidden from the booking form.
    - Validation passes without entering a license, and the payload sets `licenseNumber: null`.
    - Receipt / summary displays `"Rental Type: With Driver (Chauffeur-Driven)"`.
  - **Self-Drive Flow**:
    - When `hireWithDriver == false` (`SELF_DRIVE`), the Driver's License Number field is visible and marked required (`*`).
    - Submitting an empty field displays error: `"Driver's license number is required for self-drive bookings."`.
    - Entering a valid license allows proceeding to payment and sets `licenseNumber: "N01-XX-XXXXXX"`.
  - **Real-Time Mode Switch Invariant**:
    - Toggling from Self-Drive to With Driver clears the controller and forces `licenseNumber: null` in the payload, preventing stale license leakage.

---

## 8. Rental Listing Card Gesture Routing & Book Now CTA [VERIFIED & ENFORCED]
* **Rules**:
  - **Full-Card Tap $\rightarrow$ Detail Modal**:
    - Tapping/clicking anywhere on the card body (image thumbnail, vehicle/property title, badges, specs, price, or empty container area) opens the detailed view modal / dialog (`_openDetailDialog` on Mobile, `BookVehicleModalComponent` on Web).
    - Desktop/Web cards render with `cursor-pointer`, `card-hover`, and border highlight.
    - Mobile cards are wrapped in `Material` + `InkWell` with `SystemMouseCursors.click` and standard touch ripples.
  - **Dedicated "Book Now" / "Rent Now" Fast-Track Button**:
    - Direct CTA button on the card triggers the booking / date selection flow (`_openBookingSheet` on Mobile, `showBookVehicleModal` on Web).
    - Tapping the CTA button stops event bubbling (`e.stopPropagation()` on Web, Flutter nested widget gesture absorption on Mobile), isolating the trigger and preventing duplicate dialogs/page pushes.
  - **Multi-Category Uniformity**:
    - Applies consistently across Vehicles, Heavy Equipment, and Properties.

---

## 9. Persistent Calendar Availability, Span Conflict & Smart Tiered Rate Optimization [VERIFIED & ENFORCED]
* **Rules**:
  - **Dedicated Start & End Date Pickers with Bi-directional Sync**:
    - Web and Mobile interfaces provide explicit date pickers for **Start Date** and **End Date** (`<input type="date">`).
    - Users can freely choose any Start Date and End Date (e.g. Start: Aug 25, End: Aug 27 $\rightarrow 2$ days; or 5 days, 10 days).
    - Changing Start Date or End Date automatically recalculates `_quantity` and updates the calendar active range band.
    - Adjusting the `_quantity` multiplier/stepper automatically updates the computed End Date picker value in real time.
  - **Persistent Visualizer Calendar (Non-clickable Days, Clickable Month Navigation)**:
    - Calendar day cells are non-clickable visual elements (`cursor-default`), preventing accidental single-day click overrides.
    - Month navigation (`<` / `>`) remains fully interactive (`cursor-pointer`) so users can check reservations in upcoming months.
    - Clear visual states: Available, Booked/Reserved (red), Active Span (purple band), Start/End Dates (purple badge with ring), Overlap Conflicts (pulsing red border `border-2 border-red-500 bg-red-500/30`), Past Dates (dimmed).
  - **Unavailable / Unoffered Rental Package Locking**:
    - If a package rate is not offered (`price <= 0` or missing in listing), the option card is rendered with dimmed opacity (`opacity-40 cursor-not-allowed select-none`), displays an `"Unavailable"` / `"Not Offered"` badge, and has no click handler.
    - Initialization defaults `_selectedPackage` to the first available offered rate.
  - **Span Conflict & Overlap Blocking**:
    - Iterates every day from `_startDate` to `_computedEndDate`.
    - If any day overlaps an existing reservation:
      - Overlapping dates pulse red on the calendar.
      - Inline error alert displays: `"Selected duration overlaps with an existing reservation on [Conflicting Date(s)]. Please choose a different start date or shorter duration."`.
      - "Review Contract" / Proceed CTA is disabled.
  - **Time Formatting Standard (`HH:mm aa` / `hh:mm a`) & Payload Integrity**:
    - All time pickers, dropdown options, and schedule summary labels format time in 12-hour format with zero-padded 2-digit hours, minutes, and AM/PM markers (e.g. `Starts: Aug 25, 2026 • 09:00 AM`, `Ends: Aug 27, 2026 • 09:00 AM`).
    - Dispatching booking requests assigns `startDate` and `endDate` from `_startDate.millisecondsSinceEpoch` and `_calculatedEndDate.millisecondsSinceEpoch`.
  - **Smart Tiered Rate Engine (`SmartRateEngine`)**:
    - **7-Day Threshold**: Automatically converts 7 days (or multiple of 7) to Weekly Rate instead of $7 \times \text{Daily Rate}$.
    - **30-Day Threshold**: Automatically converts 30 days to Monthly Rate.
    - **Hybrid Durations**: Decomposes days into optimal tier sum (e.g. 10 days = 1x weekly + 3x daily).
    - **Price Capping Rule**: If $N \times \text{Daily Rate} > \text{Weekly Rate}$ (e.g. 5 days @ ₱1,000 > ₱4,500 weekly), automatically caps base price at cheaper Weekly Rate and displays optimization savings badge.
    - **Live Price Breakdown**: Real-time breakdown updates dynamically with applied tiers, capping notices, promo discounts, and escrow fees.

---

## 10. Dynamic & Immutable Counterparty Identity Verification in Rental Contracts & Summaries
- **Core Architecture & Threat Model Resolution**:
  - **Hardcoded Template Elimination**: Removed all static template strings certifying parties as "(Verified Account)" or "Verified Landlord".
  - **Dynamic Fallback Evaluation (`PartyVerificationHelper`)**:
    - Evaluates authentic database records: `idVerified == true`, `verificationLevel >= 2`, or explicit `verificationStatus == 'VERIFIED'`.
    - Returns `"Identity Status: Verified (Government ID Verified)"` (or specific tier e.g. Level 3 Pro) with green badges and checkmarks when KYC is complete.
    - Returns `"Identity Status: Unverified Account"` in amber/zinc without trust badges or checkmarks when KYC is unverified, null, or false.
  - **Immutable Contract Snapshots (`/rental_contracts/{contractId}`)**:
    - When vehicle or property rental agreements are signed, a permanent snapshot is frozen containing:
      - `hostId`, `hostName`, `hostIsVerified`, `hostVerificationStatus`, `hostVerificationTier`
      - `renteeId`, `renteeName`, `renteeIsVerified`, `renteeVerificationStatus`, `renteeVerificationTier`
      - `signatureHash`, `signedAt`, `isImmutableSnapshot: true`
    - Prevents past executed contracts from mutating retroactively if a user later updates their profile or KYC status.
  - **Contract & Transaction View Parity**:
    - Dynamic verification cards in `contract_viewer.dart`, `contract_drafts.dart`, `book_vehicle_modal.dart`, `book_property_modal.dart`, and `firebase_service.dart`.

---

## 11. LTO Registration & Comprehensive Insurance Compliance Form Integration
- **Context & Resolution**:
  - Previously, generated contracts contained a section for "3. LTO REGISTRATION & COMPLIANCE", but the vehicle listing wizards had no inputs for these fields, resulting in hardcoded `'PENDING'` and `'N/A'` values in contracts and database documents.
  - Added dedicated form sections in both Web ([`list_vehicle_modal.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/components/list_vehicle_modal.dart)) and Mobile ([`listing_wizard_sheet.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile/lib/features/transit/presentation/widgets/listing_wizard_sheet.dart)) with inputs for:
    - **LTO Certificate of Registration (CR Number)**
    - **LTO Official Receipt (OR Number)**
    - **Insured Vehicle Market Value (₱)**
    - **Comprehensive Insurance Provider** (dropdown with Philippine providers: Standard Insurance, Malayan, FPG, Pioneer, Mercantile, Alpha, Charter Ping An, or CTPL Only)
    - **Insurance Policy Reference Number**
  - Updated contract preview in Step 4 and submission handlers to bind, sanitize, and save these values to Firestore, accurately reflecting them in the generated P2P agreements.

---

---

## 12. Transparent Gig Filtering Engine & Live Active Summary Strip (`AC-GIG-01` to `AC-GIG-10`)
- **Context & Resolution**:
  - Implemented pure Dart [`GigFilterEngine`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/shared/lib/src/gig_filter_engine.dart) evaluating the filtering matrix $\text{Match} = \text{Category Rule} \land \text{Modality/Distance Rule}$.
  - Remote gigs bypass physical distance checks when Remote is ON, and are strictly excluded when Remote is OFF.
  - On-site gigs are evaluated with Haversine distance from user coordinates against the selected radius (5 km, 15 km, 30 km, 50 km, 100 km, Any Distance).
  - Category presets support `"All"`, `"Recommended"` (regex boundary matching on user skills), and `"High Paying"` (`payout >= 1000.0`).
  - Added live **Active Filter Summary Strip** showing category, distance, remote modality, and total matching count with `"Clear All"` reset button on both Web and Mobile.
  - Integrated Zero Results state with `"No available gigs match your current filters"` and a prominent `"Reset Filters"` CTA button.

---

## 13. Role-Based Search Bar Exclusivity (`AC-SEARCH-01`)
- **Context & Resolution**:
  - The home search input and global search bar are now strictly restricted to Nyxians (`isNyxian == true` / `AccountType.nyxian`).
  - For Employers (`AccountType.employer`), search inputs have been removed from the Home view across both Web and Mobile so employer accounts focus on creating listings and managing contracts rather than browsing gigs.

---

---

## 14. Interactive Walkthrough & Verification Badge System (`AC-ONBOARD-01` to `AC-ONBOARD-05`)
- **Context & Resolution**:
  - Implemented the `VerificationLevel` enum (`none`, `level1Basic`, `level2Pro`) in `packages/shared/lib/src/enums.dart`.
  - Built reusable [`UserBadgeWidget`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile/lib/core/widgets/user_badge_widget.dart) (Flutter) and [`UserBadgeComponent`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/components/user_badge_component.dart) (Jaspr):
    - **Unverified Users (`VerificationLevel.none`)**: Renders `SizedBox.shrink()` (0 badge icons, zero misleading certified labels).
    - **Level 1 Basic (`VerificationLevel.level1Basic`)**: Cyan shield badge (`VERIFIED`).
    - **Level 2 Pro (`VerificationLevel.level2Pro`)**: Upgraded Gold shield badge (`PRO`).
    - Tapping opens a bottom sheet modal breaking down Government ID, Biometric Liveness, and Merchant/Business records.
  - Built [`InteractiveWalkthroughOverlay`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile/lib/core/widgets/interactive_walkthrough_overlay.dart):
    - Dims background scrim and creates live spotlight cutout highlights around core UI targets with glowing pulse animations.
    - 4 Sequential Steps: 1. Trust & Verification Badges, 2. Rentals & Calendar Availability, 3. Jobs & Live Execution Tracking, 4. MWA Web3 Wallet & Fiat Ledger.
    - Auto-triggers on first launch with persistent `has_seen_onboarding` local storage flag in `SecureStorageHelper`.
    - Supports on-demand replay from Settings > Help & Support > "App Guide & Verification Levels" in Profile.
  - Verified with 100% passing test suite in `packages/tranyx_mobile/test/user_badge_and_walkthrough_test.dart`.

---

## 16. Pre-Hire Job Editing & Anti-Exploitation Contract Guardrails (`firestore.rules:L110-137`)
- **Context & Problem Statement**:
  - QA observed that clicking "Edit" on a job posting had no effect (empty event handler in `jobs_view.dart`, missing edit action in mobile `job_details_view.dart`).
  - No designated `updateJobDetails` existed in `FirebaseService` (web) or `JobRepository` (mobile).
- **Core Invariants & Rules**:
  - **Strict Post-Hire Lockout (Anti-Exploitation Contract)**:
    - If `job.acceptedApplicantId != null` or status is `In Progress`, `Done`, `Completed`, `Cancelled`, or `Admin Cancelled`, editing is strictly forbidden.
    - Attempting to update a post-hire gig throws an exception immediately at the service/repository layer and is blocked by `firestore.rules`.
    - Client UI unconditionally hides the Edit button or displays a disabled state when post-hire.
  - **Allowed Lifecycle States**:
    - Editing is strictly permitted only when `status.toLowerCase() in ['open', 'reviewing'] && acceptedApplicantId == null`.
  - **Strict Whitelist Alignment (`firestore.rules`)**:
    - Update payload is strictly filtered to whitelisted keys: `['title', 'description', 'category', 'categoryGroup', 'dateRequirement', 'jobDate', 'timePreference', 'locationType', 'address', 'landmark', 'pickupAddress', 'destinationAddress', 'pickupLat', 'pickupLng', 'destinationLat', 'destinationLng', 'imageUrls', 'updatedAt']`.
    - Pricing (`pricingValue`, `pricingType`) and ownership/escrow keys are locked read-only to safeguard escrow balances.
  - **Pre-Hire Edit Badge**:
    - Any successful update stamps `updatedAt` with the current timestamp.
    - When `job.isEdited` (`updatedAt != null`), both Web and Mobile show an `"Edited on [Date]"` badge chip to keep applicants informed of requirement updates.
- **Components & Implementations**:
  - **Shared Domain**: `Job.isPreHire`, `Job.canEdit`, `Job.isEdited`, `Job.formattedEditedDate`, `formatEditedDate(dynamic)`.
  - **Web**: [`EditJobModal`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/components/edit_job_modal.dart), `FirebaseService.updateJobDetails`, state management in `AppState` / `tranyx_app.dart`, and wired edit button in `jobs_view.dart`.
  - **Mobile**: [`EditJobSheet`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile/lib/features/jobs/presentation/widgets/edit_job_sheet.dart), `JobRepository.updateJobDetails`, and edit action bar button in `job_details_view.dart`.
  - **Rules**: Appended `'updatedAt'` to `firestore.rules` affected keys for employer job updates.
- **Test Coverage**:
  - `packages/tranyx_mobile/test/job_repository_test.dart` (Scenarios 1-5 verifying pre-hire edits, whitelisting, status lockout, post-hire rejection).
  - `packages/tranyx_web/test/job_edit_contract_test.dart` (Scenarios verifying model pre-hire checks, status lockout, edited badge formatting, and whitelist filtering).

---

## 17. QA Acceptance Criteria Reference
* Detailed specifications, user stories, state matrices, and test case mappings are recorded in:
  - [`qa_acceptance_criteria_matrix.md`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/.agents/memory/qa_acceptance_criteria_matrix.md)

---

## 18. Web & Dart2js Safe Map Deserialization Invariant (Prevention of `minified:c6<dynamic, dynamic>` TypeErrors)
- **Context & Problem Statement**:
  - In web production builds compiled via `dart2js`, generic `Map<dynamic, dynamic>` instances decoded from JSON or Firestore REST API are minified as `minified:c6<dynamic, dynamic>`.
  - In Dart 3+ strong typing, `<dynamic, dynamic>` is NOT a subtype of `<String, dynamic>`. Direct casts like `map as Map<String, dynamic>` or `val['securityDepositPolicy'] as Map<String, dynamic>` immediately trigger runtime `TypeError: Instance of 'minified:c6<dynamic, dynamic>': type 'minified:c6<dynamic, dynamic>' is not a subtype of type 'Map<String, dynamic>'`.
  - This occurred when renting a property in `BookPropertyModalComponent` during `PropertyPricingModel.fromPropertyMap` and `createPropertyBookingRequest` / `getPropertyPendingRequestsForRenter`.
- **Core Invariants & Rules**:
  - **Relax Model Factory Parameter Types**:
    - Domain deserializers (`PropertyRental.fromMap`, `PropertyPricingModel.fromPropertyMap`, `PlatformFeeConfig.fromMap`) must accept `Map` (untyped) rather than `Map<String, dynamic>`.
  - **Safe Nested Map Access**:
    - Never write `map['nested'] as Map<String, dynamic>`.
    - Check with `if (map['nested'] is Map)` and cast to untyped `final nested = map['nested'] as Map;` before accessing keys.
  - **No Hard Casts on Decoded JSON**:
    - When handling results from `jsonDecode(...)` or Firestore REST:
      - Use `as Map` instead of `as Map<String, dynamic>`.
      - If a typed `Map<String, dynamic>` is required by state or component signatures, construct it safely with `Map<String, dynamic>.from(rawMap as Map)` or `<String, dynamic>{ for (final e in rawMap.entries) e.key.toString(): e.value }`.
  - **Realtime Stream Decoders**:
    - In `tranyx_app.dart` JS interop callbacks (`listenToPropertiesJs`, `listenToRentalsJs`, `listenToJobsJs`, `listenToNotificationsJs`), parse array entries using `Map<String, dynamic>.from(e as Map)` or pass `e as Map` directly to factory constructors.
  - **Documented & Verified**:
    - Unit tested in `packages/shared/test/property_pricing_model_test.dart` ("Deserialization from untyped Map<dynamic, dynamic> with nested policy succeeds").











