# Antigravity Workspace Guidelines & Operational Memory

## Git Commit & Push Workflow
- **Commit Each Feature Separately**: When working on features, tasks, or bug fixes, always stage and commit each distinct unit of work separately with clear, conventional commit messages (`feat: ...`, `fix: ...`, `refactor: ...`, `test: ...`). This provides a clear, granular ledger of completed work.
- **NEVER Push to Remote**: NEVER execute `git push`. The user maintains full control and will decide when to push and squash commits to remote. All commits made by the agent must remain strictly local.

## Image Upload Policy
- **Rule**: All image uploading must be performed using the `ImgBBService` (or `imageBBService`).
- **Reasoning**: Directly uploading/storing large Base64 Data URLs inside Firestore documents exceeds Firestore's 1MB document size limit, causing database errors. Always upload images to ImgBB and store the returned HTTP URLs in Firestore.

## Firestore Security Rules & Cross-Project Deploy Collisions
- **Symptom**: Unexplained `FIRESTORE QUERY ERROR: 403 - Missing or insufficient permissions. PERMISSION_DENIED` on collections that should be readable/writable (e.g., `jobs`, `wallets`, `rentals`, `rental_requests`, `transactions`).
- **Root Cause**: The developer machine may have multiple projects (e.g., `VieXpress`, `Tranyx`) sharing Firebase CLI authentication or project IDs. Deploying security rules from an external repo can accidentally overwrite `tranyx-dev`'s Firestore rules with unrelated rules (e.g. `patients`, `prescriptions`).
- **Remediation**: Re-deploy the repository's rule set from `/Users/zeuscajurao/Desktop/tranyx_workspace`:
  ```bash
  firebase deploy --only firestore:rules --project tranyx-dev
  ```
  This immediately reinstates Tranyx's comprehensive rules for jobs, wallets, rentals, properties, and escrow transactions.
