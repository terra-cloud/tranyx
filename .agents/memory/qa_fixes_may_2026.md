# Agent Memory - QA Fixes (May 2026)

This document records the solutions and technical implementations for 5 QA bugs reported in the live environment and the unread chat badge feature.

---

## 1. Gmail Login WebView Redirect Fallback
- **Problem:** Inside Telegram Web App (TWA) WebViews, popups (`signInWithPopup`) are blocked or fail to communicate with parent frames.
- **Fix:** Added a fallback mechanism inside `index.html`'s `window.signInWithGoogle` to automatically redirect the parent page using `signInWithRedirect` when popups fail. Upon page reload, `window.checkRedirectResultJs` fetches the result using `getRedirectResult()`.
- **Affected files:**
  - `packages/tranyx_web/web/index.html` (Implemented `signInWithGoogle` fallback & `checkRedirectResultJs`)
  - `packages/tranyx_web/lib/services/web_interop_browser.dart` (Bindings for `checkRedirectResultJs`)
  - `packages/tranyx_web/lib/services/web_interop_stub.dart` (Stubs for `checkRedirectResultJs`)
  - `packages/tranyx_web/lib/client/tranyx_app.dart` (Checked redirect result on startup and handled `{ redirecting: true }`)

## 2. Real-time Chat Notifications
- **Problem:** Sending chat messages only updated the `chats` collection but did not create notification items, meaning recipients didn't see new-chat updates.
- **Fix:** In `index.html`'s `window.sendChatMessage`, added asynchronous lookup of the recipient's UID (by reading the parent job/rental/property listing document) and created a notification document inside `/notifications` with `type: 'chat'` and the corresponding `chatId`.
- **Affected files:**
  - `packages/tranyx_web/web/index.html`

## 3. Services: Nyxian Payment Release Code Binding
- **Problem:** The text `input` component in `jobs_view.dart` was untyped (`input` vs `input<String>`), causing its `onInput: (dynamic v)` handler's type casting to fail or fail to bind the state value correctly. As a result, the release button was never enabled because the length of the verification input stayed at 0.
- **Fix:** Converted the element to `input<String>` with `onInput: (String v)` to ensure the value updates state properly.
- **Affected files:**
  - `packages/tranyx_web/lib/client/views/jobs_view.dart`

## 4. Pending Completion Job Status ('Done')
- **Problem:** Jobs with a status of `'Done'` (work complete, awaiting payment release) disappeared from the user's active jobs list.
- **Fix:** In `canPostJob` and `firstActiveJob` getters, ensured that `'done'` is not included in the list of terminal states (`completed`, `complete`, `cancelled`, `closed`).
- **Affected files:**
  - `packages/tranyx_web/lib/client/tranyx_app.dart`

## 5. Vehicle/Property Request Submissions & Casting
- **Problems:**
  - Strict vehicle driver's license length validation required exactly 11 characters.
  - Runtime exceptions occurred when casting `totalCost` (deserialized as integer when no decimals are present) directly to a `double`.
  - Property bookings did not save the license/Gov-ID number and did not refresh pending lists on completion.
- **Fixes:**
  - Relaxed license length check to `length < 5` in `book_vehicle_modal.dart`.
  - Cast `totalCost` values using `(value as num).toDouble()` in all deposit handlers in `tranyx_app.dart`.
  - Added `licenseNumber` field support in property request documents via `createPropertyBookingRequest` and `approvePropertyBookingRequest` in `firebase_service.dart`.
  - Saved `licenseNumber` in `book_property_modal.dart` and called `loadRenterPendingRequests()` on success.
- **Affected files:**
  - `packages/tranyx_web/lib/client/components/book_vehicle_modal.dart`
  - `packages/tranyx_web/lib/client/components/book_property_modal.dart`
  - `packages/tranyx_web/lib/client/tranyx_app.dart`
  - `packages/tranyx_web/lib/services/firebase_service.dart`

## 6. Chat Badge Count Feature
- **Problem:** No visual indicator for unread chat messages.
- **Fix:**
  - Added real-time notification helpers in `tranyx_app.dart` (`getUnreadChatCount`, `hasUnreadJobChats`, `hasUnreadRentalChats`).
  - Synced active chats to auto-read incoming notifications and mark existing ones read when a chat is opened.
  - Added pulsing dot indicators on `BottomNavComponent` and `SidebarComponent`.
  - Added numeric count badge indicators on all P2P chat buttons.
- **Affected files:**
  - `packages/tranyx_web/lib/client/tranyx_app.dart`
  - `packages/tranyx_web/lib/client/views/jobs_view.dart`
  - `packages/tranyx_web/lib/client/views/transit_view.dart`
  - `packages/tranyx_web/lib/client/components/manage_property_modal.dart`
  - `packages/tranyx_web/lib/client/components/manage_vehicle_modal.dart`
  - `packages/tranyx_web/lib/client/widgets/bottom_nav.dart`
  - `packages/tranyx_web/lib/client/widgets/sidebar.dart`
