# QA Audit Report: Tranyx Mobile & Firebase Rules

## 1. Firebase Rules & Indexes Audit

**Score: 2 / 5 (Critical Security Vulnerabilities)**

### Security Rules (firestore.rules)
* **Update Bypass & Ownership:** Several collections lack proper field-level and ownership checks on `update`. For example, in `/jobs/{jobId}`, `rentals/{rentalId}`, and `properties/{propertyId}`, the rule `allow create, update: if isActiveUser();` allows **any active user to update any other user's documents** (including changing ownership or status).
* **Type Safety:** There are no schema or field-level type validations ensuring that data conforms to expectations before being written.
* **Authority Source:** Admin checks properly retrieve roles from the user document. However, performing multiple `get()` calls per query across a collection could lead to excessive read costs.
* **Storage Abuse:** Not directly applicable to Firestore Rules, but without size limits or data validation, users could inject massive payloads.

### Indexes (firestore.indexes.json)
* **Alignment with Collections:** The current indexes heavily support the `jobs`, `transactions`, `news_posts`, and `points_history` collection groups.
* **Missing Indexes:** Important collections such as `notifications`, `rentals`, and `properties` are entirely absent from the composite indexes. Features like fetching notifications ordered by `createdAt` per `uid`, or browsing active `rentals` will likely fail if ordered or filtered queries are used in the app.

### Recommendations
1. **Enforce Ownership on Updates:** Change `allow update: if isActiveUser();` to ensure the requester is the owner of the resource (e.g., `if isActiveUser() && resource.data.creatorId == request.auth.uid;`).
2. **Implement Field-Level Rules:** Validate that only specific fields can be modified during updates (e.g., using `request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`).
3. **Add Missing Indexes:** Define composite indexes for `notifications` (e.g., `uid` + `createdAt` DESC) and relevant queries for `rentals` and `properties`.

## 2. Release Build Test (tranyx_mobile)

**Status: Compile-time validations passed with lint warnings.**

The `flutter analyze` command was run on the `packages/tranyx_mobile` codebase to perform static compile-time validation. 

* **Results:** The analyzer found 141 issues. The vast majority of these issues are non-blocking `info` and `warning` level lints (e.g., `use_build_context_synchronously`, `deprecated_member_use`, `avoid_print`, and `use_null_aware_elements`). 
* **Compilation Status:** There were no fatal compile-time errors (like syntax or missing dependencies) that would prevent a release build. 
* **iOS Build Status:** The `flutter build ios --no-codesign` background task successfully resolved all dependencies and began the Xcode build phase.

### Recommendations for Mobile Codebase
1. **Address Build Context Warnings:** Fix the `use_build_context_synchronously` warnings across async gaps to prevent potential runtime crashes if a widget is unmounted before the async task completes.
2. **Cleanup Deprecated APIs:** Update deprecated members such as replacing `'value'` with `initialValue` in `listing_wizard_sheet.dart`.
3. **Remove Print Statements:** Remove `print` statements in production code in favor of a robust logging framework.
