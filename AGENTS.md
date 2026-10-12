# Antigravity Workspace Guidelines & Operational Memory

## Git Commit & Push Workflow
- **Commit Each Feature Separately**: When working on features, tasks, or bug fixes, always stage and commit each distinct unit of work separately with clear, conventional commit messages (`feat: ...`, `fix: ...`, `refactor: ...`, `test: ...`). This provides a clear, granular ledger of completed work.
- **NEVER Push to Remote**: NEVER execute `git push`. The user maintains full control and will decide when to push and squash commits to remote. All commits made by the agent must remain strictly local.

## Image Upload Policy
- **Rule**: All image uploading must be performed using the `ImgBBService` (or `imageBBService`).
- **Reasoning**: Directly uploading/storing large Base64 Data URLs inside Firestore documents exceeds Firestore's 1MB document size limit, causing database errors. Always upload images to ImgBB and store the returned HTTP URLs in Firestore.

## Firestore Security Rules Cross-Project Synchronization (`tranyx_workspace` & `tranyx_admin_portal`)
- **Shared Architecture**: Both `tranyx_workspace` (Web & Mobile) and `tranyx_admin_portal` (Admin Desk) interact with the same Firestore database environments (`tranyx-dev`, `tranyx-uat`, `tranyx-app`).
- **Single Source of Truth**: `tranyx_workspace/firestore_rules/` is the sole authoritative source of truth for all Cloud Firestore security rules across the platform.
- **Automated Cross-Project Sync**:
  - Running `dart run tool/build_rules.dart` compiles the 10 modular rule files in `firestore_rules/` into `firestore.rules` and automatically mirrors the exact file to `../tranyx_admin_portal/firestore.rules`.
  - In `tranyx_admin_portal`, a `predeploy` lifecycle hook in `firebase.json` automatically triggers `dart run tool/sync_rules.dart` before every deployment, preventing any stale or conflicting rules from being published.
- **Rule Authoring & Deployment Protocol**:
  - All Firestore rule additions/modifications must be made in `tranyx_workspace/firestore_rules/` (delegated to the `firestore-rules-author` subagent).
  - Compile via `dart run tool/build_rules.dart`.
  - Deploy safely via `dart run tool/deploy_rules.dart [dev|uat|prod|all]`.
  - NEVER author independent, divergent rules in `tranyx_admin_portal/firestore.rules`.
- **Remediation for Collisions**: If an external project or accidental deployment disrupts database permissions:
  ```bash
  dart run tool/deploy_rules.dart dev
  ```
  This immediately reinstates Tranyx's comprehensive rules across all collections.
