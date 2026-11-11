# Production release runbook (tranyx-app)

Web and backend only. Do not publish mobile. Do not deploy to `tranyx-dev` or `tranyx-uat`, and do not upgrade `tranyx-dev` (it stays on Spark).

Run the steps in the order below. Claims have to exist before the new functions and the new rules, or staff money actions and private account reads fail. The new web has to be live, with the new rules, before the listing-address migration, or signed-in users lose street addresses.

Every Firebase command includes `--project tranyx-app`. `.firebaserc` sets `projects.default` to `tranyx-app`, so a command that omits `--project` publishes production.

## Blockers to clear before step 1

These were not executed against production from the prep environment.

1. **Mobile workflow.** `develop` differs from `main` under `packages/tranyx_mobile/**`. Pushing `main` runs `.github/workflows/tranyx-mobile-publish.yml` whenever that path changed. This release is web and backend only. Decide how to keep that workflow from publishing mobile before merging to `main`.
2. **Secrets, by name only.** `requestWithdrawal`, `reconcileWithdrawals`, and `staffOps` require Secret Manager secret `SOLANA_TREASURY_SECRET_KEY`. `uploadImageProxy` requires `IMGBB_API_KEY`. A missing secret fails the functions deploy. Confirm the names exist (step 1). Do not print the values.
3. **Treasury public key.** `functions/.env.tranyx-app` does not set `SOLANA_TREASURY_PUBLIC_KEY`. An empty value makes withdrawals read `system_config/treasury.publicKey`. Confirm that document has the current treasury public key before the withdrawal smoke test.
4. **Hosting result.** `.github/workflows/jaspr-hosting-merge.yml` sets `continue-on-error: true` on the hosting deploy. A green workflow can still hide a failed production hosting deploy. Read that step's log.
5. **Hosting site.** `firebase.json` has one hosting site. `.firebaserc` lists sites `tranyx-dev`, `tranyx-prod`, and `tranyx-uat` on project `tranyx-app`, and the workflow does not set a hosting target. Before announcing, confirm the live channel is the production site.

## 1. Pre-flight

```bash
npx firebase-tools@15.5.1 --version
npx firebase-tools@15.5.1 login:list
npx firebase-tools@15.5.1 projects:list
```

The account in `login:list` must be allowed to deploy `tranyx-app`. `projects:list` must include `tranyx-app`.

```bash
gcloud secrets describe SOLANA_TREASURY_SECRET_KEY --project tranyx-app
gcloud secrets describe IMGBB_API_KEY --project tranyx-app
gcloud secrets versions list SOLANA_TREASURY_SECRET_KEY --project tranyx-app
gcloud secrets versions list IMGBB_API_KEY --project tranyx-app
```

`describe` and `versions list` show metadata, not the secret value. Do not run `firebase functions:secrets:get` or `gcloud secrets versions access`.

Params already named in `functions/.env.tranyx-app` (values stay in that file, not in chat):

- `SOLANA_RPC_URL`
- `SOLANA_USDT_MINT`
- `ENFORCE_APP_CHECK`

Confirm locally that `ENFORCE_APP_CHECK` is `true`. Leave it true for this release.

Optional params with code defaults, not required in that file:

- `SOLANA_TREASURY_PUBLIC_KEY` (empty means `system_config/treasury.publicKey`)
- `WALLET_AUTH_DOMAINS` (default includes `tranyx.app`)

Service accounts for the data tools, as file paths, never committed:

- `ADMIN_GOOGLE_APPLICATION_CREDENTIALS` — read `users` on `tranyx-admin` (claims sync source)
- `TARGET_GOOGLE_APPLICATION_CREDENTIALS` — Firebase Auth Admin and Cloud Datastore User on `tranyx-app`
- `GOOGLE_APPLICATION_CREDENTIALS` — used for the target only when `TARGET_GOOGLE_APPLICATION_CREDENTIALS` is unset

## 2. What a merge deploys

Branch protection in `.github/workflows/ruleset.yml`:

- `uat` accepts a merge only from `develop`
- `main` accepts a merge only from `uat`

Do this merge **after** steps 3–6, not before. Pushing `main` is the production web deploy.

```bash
git fetch origin
git checkout uat && git pull origin uat
git merge origin/develop
git push origin uat

git checkout main && git pull origin main
git merge origin/uat
git push origin main
```

On that `main` push, if `packages/tranyx_web/**`, `packages/shared/**`, or the hosting workflow changed:

- `.github/workflows/jaspr-hosting-merge.yml` builds with `ENV=prod` and deploys hosting to project `tranyx-app`, channel `live`.

If `packages/tranyx_mobile/**` changed (it has, relative to current `main`):

- `.github/workflows/tranyx-mobile-publish.yml` builds and publishes the mobile app. That is outside this release. See the blocker above.

No workflow deploys functions, Firestore rules, or indexes. Those stay manual, below.

## 3. Staff claims, before functions and rules

Source of truth: `users` on `tranyx-admin` where `isAdmin`, `isStaff`, or `isSuperAdmin` is true. Admin and superadmin get `{ admin: true, role: 'admin' }`. Staff-only get `{ admin: false, role: 'staff' }`.

`--revoke` is not part of this release. Omit it unless you intend to remove claims.

```bash
export ADMIN_GOOGLE_APPLICATION_CREDENTIALS=/path/to/tranyx-admin-reader.json
export TARGET_GOOGLE_APPLICATION_CREDENTIALS=/path/to/tranyx-app-admin.json

node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod
node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply
```

The first command only prints `grant` and `wouldRevoke`. The second writes claims and logs each `setCustomUserClaims`. Running it again skips users whose claims already match.

Each staff and admin person signs out of the web app and signs back in. An existing ID token keeps the old claims until then. New rules and `staffOps` ignore `users.isAdmin` / `users.isStaff` document flags.

## 4. Functions

Still before the rules, and only after step 3.

```bash
npx firebase-tools@15.5.1 deploy --only functions --project tranyx-app
```

This uses `functions/.env.tranyx-app` and the two secrets from step 1. `staffOps` requires `SOLANA_TREASURY_SECRET_KEY` and a custom claim. Staff who have not signed in again still fail closed until they do.

## 5. Public profile backfill, before the rules

After the rules deploy, clients can no longer read another person's `users/{uid}`. Counterparties need `public_profiles/{uid}` first. The tool copies only the public card (name, photo, headline, skills, rating, and the other allowlisted fields). It does not copy email, phone, wallet, balances, KYC, or `idVerified`.

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$TARGET_GOOGLE_APPLICATION_CREDENTIALS"

node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod
node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod --apply
```

Dry-run prints uids and field names. Apply logs each `set`. A second apply skips cards that already match. Each write is also recorded at `purge_audit/public_profiles_<timestamp>` when at least one card changed.

## 6. Rules and indexes, after claims

```bash
npx firebase-tools@15.5.1 deploy --only firestore:rules,firestore:indexes --project tranyx-app
```

Rules in this deploy:

- staff and admin money paths require the custom claims from step 3
- `users/{uid}` is readable by the owner or claim staff; other people use `public_profiles/{uid}`
- exact listing address and coordinates are not client-writable on the public job, property, or vehicle document
- `{jobs|properties|rentals}/{id}/private/location` is readable by any signed-in user

Index builds do not block reads. Wait until the rules deploy reports success before the web merge.

## 7. Web hosting

Merging `uat` into `main` (step 2) is the production hosting deploy when web files changed. Do that now.

Watch the `Deploy to Firebase Hosting (prod)` step. `continue-on-error: true` means the job can look green when hosting failed.

If you deploy hosting by hand instead, from a checkout of the release SHA, with the same defines the workflow uses (values come from GitHub Actions secrets and variables; do not echo them):

```bash
cd packages/tranyx_web
jaspr build --dart-define=ENV=prod \
  --dart-define=XENDIT_SECRET_KEY="$XENDIT_SECRET_KEY" \
  --dart-define=IMGBB_API_KEY="$IMGBB_API_KEY" \
  --dart-define=BASEMAPS_API_KEY="$BASEMAPS_API_KEY" \
  --dart-define=GEMINI_AI_API_KEY="$GEMINI_AI_API_KEY" \
  --dart-define=SOLANA_PUBLIC_KEY="$SOLANA_PUBLIC_KEY"
cd ../..
npx firebase-tools@15.5.1 deploy --only hosting --project tranyx-app
```

`ENV=prod` bakes in the reCAPTCHA Enterprise site key and `ReCaptchaEnterpriseProvider`. Do not pass `APPCHECK_SITE_KEY`. Do not use the old `6LfRz...` key.

## 8. Listing addresses, then completion codes

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

## 9. Smoke test

Use a real signed-in account and a staff account that has signed out and back in since step 3.

- **Guest (signed out).** Open a job, a property, and a vehicle. The address reads `Brgy. *****, ****`. The map control does not open a map. The page does not show a street or a pin from exact coordinates.
- **Signed-in user.** Open the same three listings. The full address and the map are visible. Open another person's profile card and confirm it has no email, phone, wallet, or balance.
- **Staff.** Sign out and back in. Open a staff money screen (withdrawal queue or deposit review) and confirm it loads. Do not approve your own deposit or withdrawal.
- **Admin.** With an `admin` claim, open a staff-only user lookup that a normal account cannot list.
- **Deposit.** Send one small on-chain deposit from a verified wallet. Confirm the balance increases once. Refresh and confirm it does not increase again for the same signature.
- **Withdrawal.** Request one Solana withdrawal at the configured minimum (`config/withdrawals.minPhp`, default 100 PHP). Confirm one debit, one withdrawal document, and no second debit if you retry the same action.

## 10. Rollback

Pick the last known-good git SHA (`<previous-sha>` below) before this release.

Rules:

```bash
git checkout <previous-sha> -- firestore.rules
npx firebase-tools@15.5.1 deploy --only firestore:rules --project tranyx-app
git checkout HEAD -- firestore.rules
```

Hosting:

```bash
npx firebase-tools@15.5.1 hosting:releases:list --project tranyx-app
npx firebase-tools@15.5.1 hosting:rollback --project tranyx-app
```

If `hosting:rollback` is not in the CLI, check out `<previous-sha>` and run the manual `jaspr build --dart-define=ENV=prod` plus `deploy --only hosting --project tranyx-app` from step 7.

Functions. Redeploy the previous source. Do not delete functions.

```bash
git checkout <previous-sha>
npx firebase-tools@15.5.1 deploy --only functions --project tranyx-app
git checkout -
```

Data migrations are not reversed by a redeploy. Restoring a public street address or a completion code means restoring those fields from a backup, not from git. Do not run a second `--apply` as a rollback; a second apply is a no-op on already migrated documents.

Claims are not removed by a rollback. Leave them in place unless you intentionally run `node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply --revoke`.
