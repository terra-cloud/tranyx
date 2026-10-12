# Agent Memory

## Git Commit & Push Policy
- **Rule**: When working on features or tasks, ALWAYS commit each feature or sub-task separately with clear, descriptive commit messages.
- **Rule**: NEVER run `git push` or push commits to the remote repository. The USER will decide when to push and squash commits. All commits must remain local.
- **Reasoning**: Granular commits allow the user to review what tasks are completed and squash-merge them as desired upon pushing to remote.

## Image Upload Policy
- **Rule**: All image uploading must be performed using the `ImgBBService` (or `imageBBService`).
- **Reasoning**: Directly uploading/storing large Base64 Data URLs inside Firestore documents exceeds Firestore's 1MB document size limit, causing database errors. Always upload images to ImgBB and store the returned HTTP URLs in Firestore.

## Firestore Security Rules Cross-Project Synchronization (`tranyx_workspace` & `tranyx_admin_portal`)
- **Shared Architecture**: `tranyx_workspace` (Web & Mobile) and `tranyx_admin_portal` (Admin Desk) operate against the same Firebase projects (`tranyx-dev`, `tranyx-uat`, `tranyx-app`).
- **Single Source of Truth**: `tranyx_workspace/firestore_rules/` is the single authoritative source of truth for ALL Cloud Firestore security rules.
- **Automated Sync**: `dart run tool/build_rules.dart` compiles the modular rules into `firestore.rules` and automatically mirrors them to `../tranyx_admin_portal/firestore.rules`.
- **Deployment Protocol**:
  - Author changes in `tranyx_workspace/firestore_rules/` via `firestore-rules-author` subagent.
  - Compile with `dart run tool/build_rules.dart`.
  - Deploy with `dart run tool/deploy_rules.dart [dev|uat|prod|all]`.
  - In `tranyx_admin_portal`, `firebase.json` has a `predeploy` hook executing `dart run tool/sync_rules.dart`.
  - NEVER author standalone rules inside `tranyx_admin_portal/firestore.rules`.
