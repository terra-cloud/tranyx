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

## 2. Treasury Vault, Payment Methods & On-Chain Settlement (VERIFIED & CONFIRMED)
* **Rules**:
  - **Payment Methods View**: In [`packages/tranyx_web/lib/client/views/profile_view.dart`](file:///Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_web/lib/client/views/profile_view.dart), the Phantom Wallet card is removed from the Payment Methods section.
  - **Top-Up & Subscriptions**: Platform target Solana address must always use `Env.solanaPublicKey` (Treasury Vault address) and never hardcoded test addresses (`4zMMC...`).
  - **Withdrawals (Cash-Out)**:
    - **Web**: `broadcastTreasuryTransfer` (SOL) and `broadcastTreasuryTokenTransfer` (USDT) execute direct on-chain transfers from `Env.solanaPrivateKey` via `@solana/web3.js` to the user's destination `walletPublicKey`.
    - **Mobile**: `signAndBroadcastTransfer` (SOL) and `signAndBroadcastTokenTransfer` (USDT) in `phantom_provider.dart` sign with `Env.solanaPrivateKey` via `pinenacl` Ed25519 and broadcast directly to Solana RPC.
    - Transaction signatures (`solanaTxSignature`) must be recorded in both `transactions` and `withdrawalRequests` collections with status `'Successful'` / `'Completed'`.

---

## 3. Web & Mobile Security (VERIFIED & CONFIRMED)
* **Rules**:
  - CI/CD GitHub workflows must use 40-character immutable commit SHAs for third-party actions.
  - Mobile manifest must retain `android:networkSecurityConfig="@xml/network_security_config"` and `android:allowBackup="false"`.
