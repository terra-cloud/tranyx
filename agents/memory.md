# Agent Memory

## Git Commit & Push Policy
- **Rule**: When working on features or tasks, ALWAYS commit each feature or sub-task separately with clear, descriptive commit messages.
- **Rule**: NEVER run `git push` or push commits to the remote repository. The USER will decide when to push and squash commits. All commits must remain local.
- **Reasoning**: Granular commits allow the user to review what tasks are completed and squash-merge them as desired upon pushing to remote.

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
