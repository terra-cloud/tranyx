# Production release runbook (tranyx-app)

Web and backend only. Do not publish mobile. Do not deploy to `tranyx-dev` or `tranyx-uat`, and do not upgrade `tranyx-dev` (it stays on Spark).

Run the steps in the order below. Claims have to exist before the new functions and the new rules, or staff money actions and private account reads fail. The new web has to be live, with the new rules, before the listing-address migration, or signed-in users lose street addresses.

Every Firebase command includes `--project tranyx-app`. `.firebaserc` sets `projects.default` to `tranyx-app`, so a command that omits `--project` publishes production.

## Before you start

Treasury config stays as it is. `functions/.env.tranyx-app` does not set `SOLANA_TREASURY_PUBLIC_KEY`. Withdrawals keep using the existing `system_config/treasury` public key. Do not change that document or the treasury code for this release.

Mobile publish does not run on a push to `main`. `.github/workflows/tranyx-mobile-publish.yml` still exists. Its job runs only from **Run workflow** (`workflow_dispatch`) or when the repository variable `PUBLISH_MOBILE` is exactly `true`. Leave that variable unset.

The production hosting step fails the job if the deploy fails. It publishes the live channel of the default Hosting site on project `tranyx-app`:

- site ID `tranyx-app`
- https://tranyx-app.web.app
- https://tranyx.app (same release)

Do not set a Hosting `target`. The `.firebaserc` target `tranyx-web-app` lists `tranyx-dev`, `tranyx-prod`, and `tranyx-uat`. https://tranyx-prod.web.app is not the live site.

## 1. Pre-flight

Production deploys do not run from a laptop. They run in GitHub Actions from the secrets stored there.

Confirm these GitHub Actions secret **names** exist on `terra-cloud/tranyx` (Settings → Secrets). Do not print the values.

- `SOLANA_TREASURY_SECRET_KEY`
- `IMGBB_API_KEY`
- `GEMINI_AI_API_KEY` (copied into Secret Manager as `GEMINI_API_KEY`)
- `FIREBASE_SERVICE_ACCOUNT_TRANYX_APP`

`requestWithdrawal`, `reconcileWithdrawals`, and `staffOps` read `SOLANA_TREASURY_SECRET_KEY` with `defineSecret`. `uploadImageProxy` reads `IMGBB_API_KEY`. `geminiAssist` reads `GEMINI_API_KEY`. A GitHub secret is not visible to Cloud Functions until the workflow copies it into Secret Manager. The `main` deploy does that copy, then deploys. If any of those GitHub secrets is missing, that job fails before deploy. Do not pass `XENDIT_SECRET_KEY`, `IMGBB_API_KEY`, `GEMINI_AI_API_KEY`, or `CLOUDFLARE_API_TOKEN` into the web build.

After the workflow succeeds, these commands show metadata only:

```bash
gcloud secrets describe SOLANA_TREASURY_SECRET_KEY --project tranyx-app
gcloud secrets describe IMGBB_API_KEY --project tranyx-app
gcloud secrets describe GEMINI_API_KEY --project tranyx-app
gcloud secrets versions list SOLANA_TREASURY_SECRET_KEY --project tranyx-app
gcloud secrets versions list IMGBB_API_KEY --project tranyx-app
gcloud secrets versions list GEMINI_API_KEY --project tranyx-app
```

Do not run `firebase functions:secrets:get` or `gcloud secrets versions access`.

Params already named in `functions/.env.tranyx-app` (values stay in that file, not in chat):

- `SOLANA_RPC_URL`
- `SOLANA_USDT_MINT`
- `ENFORCE_APP_CHECK`

Confirm locally that `ENFORCE_APP_CHECK` is `true`. Leave it true for this release.

`SOLANA_TREASURY_PUBLIC_KEY` is intentionally unset. The functions keep reading the existing `system_config/treasury` public key. `WALLET_AUTH_DOMAINS` is also unset and defaults to a list that includes `tranyx.app`.

Service accounts for the data tools, as file paths, never committed:

- `ADMIN_GOOGLE_APPLICATION_CREDENTIALS` — read `users` and Auth on `tranyx-admin-portal` (claims sync source)
- `TARGET_GOOGLE_APPLICATION_CREDENTIALS` — Firebase Auth Admin and Cloud Datastore User on `tranyx-app`
- `GOOGLE_APPLICATION_CREDENTIALS` — used for the target only when `TARGET_GOOGLE_APPLICATION_CREDENTIALS` is unset

## 2. What a merge deploys

Branch protection in `.github/workflows/ruleset.yml`:

- `uat` accepts a merge only from `develop`
- `main` accepts a merge only from `uat`

One push to `main` deploys functions, rules, indexes, and hosting together. Run the claims sync and the public-profile backfill first. Claims and the profile cards have to exist before that push, or staff money actions fail and counterparties lose profile reads the moment the rules land.

Workflow **Deploy hosting and production functions** (`.github/workflows/jaspr-hosting-merge.yml`) runs on a push to `main`, `uat`, or `develop` when web, shared, functions, rules, or index files changed.

For `github.ref_name == main` and a backend change, in this order:

1. `firebase functions:secrets:set` for `SOLANA_TREASURY_SECRET_KEY`, `IMGBB_API_KEY`, and `GEMINI_API_KEY` (from the GitHub secret `GEMINI_AI_API_KEY`), reading the GitHub Actions secrets on stdin (`--data-file=-`). That writes Google Secret Manager on `tranyx-app`. It does not print the values.
2. `firebase deploy --only functions,firestore:rules,firestore:indexes --project tranyx-app`.
3. If web files changed, Hosting channel `live` on the default site `tranyx-app`. Live URLs: https://tranyx-app.web.app and https://tranyx.app.

A failure in the functions, rules, or production hosting step fails the job. Dev and UAT pushes still deploy only their own hosting projects. They do not deploy functions or rules.

A push to `main` does not publish mobile. `.github/workflows/tranyx-mobile-publish.yml` stays in the repo and does not run its job unless `PUBLISH_MOBILE` is `true` or someone starts the workflow manually.

## 3. Staff claims, before the main push

Source of truth: `users` on `tranyx-admin-portal` where `isAdmin`, `isStaff`, or `isSuperAdmin` is true. That project is separate from `tranyx-app`, so an admin-portal uid is not a tranyx-app uid. The tool takes the email on the user document, or looks it up with admin-portal Auth when the document email is empty, then finds the tranyx-app user with that email and grants claims to the tranyx-app uid. It does not grant a uid that is missing from tranyx-app Auth. Unmatched people are printed with `email` and `reason` (`no-email` or `no-target-user`).

Admin and superadmin get `{ admin: true, role: 'admin' }`. Staff-only get `{ admin: false, role: 'staff' }`.

`--revoke` is not part of this release. Omit it unless you intend to remove claims. Revocation, when you do pass it, looks at tranyx-app Auth users who still have admin or staff claims and were not matched by email.

```bash
export ADMIN_GOOGLE_APPLICATION_CREDENTIALS=/path/to/tranyx-admin-portal-reader.json
export TARGET_GOOGLE_APPLICATION_CREDENTIALS=/path/to/tranyx-app-admin.json

node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod
node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply
```

The first command only prints `grant`, `unmatched`, and `wouldRevoke`. The second writes claims on the matched tranyx-app uids and logs each `setCustomUserClaims`. Running it again skips users whose claims already match.

Each staff and admin person signs out of the web app and signs back in. An existing ID token keeps the old claims until then. New rules and `staffOps` ignore `users.isAdmin` / `users.isStaff` document flags.

## 4. Public profile backfill, before the main push

After the rules deploy, clients can no longer read another person's `users/{uid}`. Counterparties need `public_profiles/{uid}` first. The tool copies only the public card (name, photo, headline, skills, rating, and the other allowlisted fields). It does not copy email, phone, wallet, balances, KYC, or `idVerified`.

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$TARGET_GOOGLE_APPLICATION_CREDENTIALS"

node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod
node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod --apply
```

Dry-run prints uids and field names. Apply logs each `set`. A second apply skips cards that already match. Each write is also recorded at `purge_audit/public_profiles_<timestamp>` when at least one card changed.

## 5. Push main

This is the production deploy. Do it only after steps 3 and 4. The workflow deploys functions, rules, indexes, and hosting in one job. Do not run `firebase deploy` from a laptop.

```bash
git fetch origin
git checkout uat && git pull origin uat
git merge origin/develop
git push origin uat

git checkout main && git pull origin main
git merge origin/uat
git push origin main
```

Rules in that deploy:

- staff and admin money paths require the custom claims from step 3
- `users/{uid}` is readable by the owner or claim staff; other people use `public_profiles/{uid}`
- exact listing address and coordinates are not client-writable on the public job, property, or vehicle document
- `{jobs|properties|rentals}/{id}/private/location` is readable by any signed-in user

`staffOps` requires `SOLANA_TREASURY_SECRET_KEY` in Secret Manager and a custom claim. Staff who have not signed in again still fail closed until they do.

Wait until the GitHub job is green. The release is then live at https://tranyx-app.web.app and https://tranyx.app.

There is no laptop fallback for this deploy. If you ever rebuild the web by hand, the defines match the workflow (values come from GitHub Actions secrets and variables; do not echo them):

```bash
cd packages/tranyx_web
jaspr build --dart-define=ENV=prod \
  --dart-define=BASEMAPS_API_KEY="$BASEMAPS_API_KEY" \
  --dart-define=SOLANA_PUBLIC_KEY="$SOLANA_PUBLIC_KEY"
cd ../..
npx firebase-tools@15.5.1 deploy --only hosting --project tranyx-app
```

That command has no Hosting target, so it publishes the default site `tranyx-app` (https://tranyx-app.web.app and https://tranyx.app). Do not pass `hosting:tranyx-web-app`.

`ENV=prod` bakes in the reCAPTCHA Enterprise site key and `ReCaptchaEnterpriseProvider`. Do not pass `APPCHECK_SITE_KEY`. Do not use the old `6LfRz...` key.

## 6. Listing addresses, then completion codes

Run these only after the new web and the new rules are both live. The new client reads exact coordinates from `private/location`. Moving them earlier hides addresses from the previous web.

```bash
node tool/migrate_listing_locations.mjs --project tranyx-app --allow-prod
node tool/migrate_listing_locations.mjs --project tranyx-app --allow-prod --apply

node tool/purge_job_completion_codes.mjs --project tranyx-app --allow-prod
node tool/purge_job_completion_codes.mjs --project tranyx-app --allow-prod --apply
```

Dry-run lists document ids and field names. It does not print street addresses or completion codes. Apply logs every `set` and `update`. A second apply skips documents that are already migrated or already purged. Audits:

- `purge_audit/listing_locations_<timestamp>`
- `purge_audit/job_codes_<timestamp>`

`--apply` without `--allow-prod`, or with `--project tranyx-dev` or `--project tranyx-uat`, exits before writing.

## 7. Smoke test

Use a real signed-in account and a staff account that has signed out and back in since step 3.

- **Guest (signed out).** Open a job, a property, and a vehicle. The address reads `Brgy. *****, ****`. The map control does not open a map. The page does not show a street or a pin from exact coordinates.
- **Signed-in user.** Open the same three listings. The full address and the map are visible. Open another person's profile card and confirm it has no email, phone, wallet, or balance.
- **Staff.** Sign out and back in. Open a staff money screen (withdrawal queue or deposit review) and confirm it loads. Do not approve your own deposit or withdrawal.
- **Admin.** With an `admin` claim, open a staff-only user lookup that a normal account cannot list.
- **Deposit.** Send one small on-chain deposit from a verified wallet. Confirm the balance increases once. Refresh and confirm it does not increase again for the same signature.
- **Withdrawal.** Request one Solana withdrawal at the configured minimum (`config/withdrawals.minPhp`, default 100 PHP). Confirm one debit, one withdrawal document, and no second debit if you retry the same action.

## 8. Rollback

Revert the release commit on `main` and push. That runs the same workflow again: it rewrites the two Secret Manager versions from the GitHub secrets, then deploys the previous functions, rules, indexes, and hosting. Do not delete functions.

Hosting only, from a machine that is already logged into `tranyx-app`:

```bash
npx firebase-tools@15.5.1 hosting:releases:list --project tranyx-app
npx firebase-tools@15.5.1 hosting:rollback --project tranyx-app
```

Data migrations are not reversed by a redeploy. Restoring a public street address or a completion code means restoring those fields from a backup, not from git. Do not run a second `--apply` as a rollback; a second apply is a no-op on already migrated documents.

Claims are not removed by a rollback. Leave them in place unless you intentionally run `node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply --revoke`.
