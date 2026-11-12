# Production release runbook (tranyx-app)

Web and backend only. Do not publish mobile. Do not deploy to `tranyx-dev` or `tranyx-uat`, and do not upgrade `tranyx-dev` (it stays on Spark).

Do not run `firebase deploy` from the Mac. Production functions, rules, indexes, and hosting go out together when `main` is pushed. Claims and the public-profile backfill are the only production writes you run locally, and both finish before that push.

Repo: `~/Desktop/tranyx_workspace`. Every Firebase command includes `--project tranyx-app`. `.firebaserc` sets `projects.default` to `tranyx-app`, so a command that omits `--project` publishes production.

## Before you start

Treasury config stays as it is. `functions/.env.tranyx-app` does not set `SOLANA_TREASURY_PUBLIC_KEY`. Withdrawals keep using the existing `system_config/treasury` public key. Do not change that document or the treasury code for this release.

Mobile publish does not run on a push to `main`. `.github/workflows/tranyx-mobile-publish.yml` still exists. Its job runs only from **Run workflow** (`workflow_dispatch`) or when the repository variable `PUBLISH_MOBILE` is exactly `true`. Leave that variable unset.

The production hosting step fails the job if the deploy fails. It publishes the live channel of the default Hosting site on project `tranyx-app`:

- site ID `tranyx-app`
- https://tranyx-app.web.app
- https://tranyx.app (same release)

Do not set a Hosting `target`. The `.firebaserc` target `tranyx-web-app` lists `tranyx-dev`, `tranyx-prod`, and `tranyx-uat`. https://tranyx-prod.web.app is not the live site.

The live web bundle at https://tranyx.app (built 15 Oct 2026) contains a Gemini API key and an ImgBB API key. Rotate both in GitHub before the push below, so the workflow copies the new values into Secret Manager. The Xendit secret key is not in that bundle. Do not print any secret value.

## 1. Mac setup

```bash
cd ~/Desktop/tranyx_workspace
git checkout develop
git pull origin develop
npm install --prefix functions
```

`npm install` belongs in `functions/`, not the repo root. Skip it when `functions/node_modules` is already present. The claims script loads `firebase-admin` from there.

```bash
export ADMIN_GOOGLE_APPLICATION_CREDENTIALS="$HOME/Documents/tranyx-admin-portal-firebase-adminsdk-fbsvc-970f004c85.json"
export TARGET_GOOGLE_APPLICATION_CREDENTIALS="$HOME/Documents/tranyx-app-firebase-adminsdk-fbsvc-569082f230.json"
export GOOGLE_APPLICATION_CREDENTIALS="$TARGET_GOOGLE_APPLICATION_CREDENTIALS"
```

`ADMIN_GOOGLE_APPLICATION_CREDENTIALS` reads `users` and Auth on `tranyx-admin-portal`. `TARGET_GOOGLE_APPLICATION_CREDENTIALS` is Firebase Auth Admin and Cloud Datastore User on `tranyx-app`.

Confirm these GitHub Actions secret **names** exist on `terra-cloud/tranyx`. Do not print the values.

- `SOLANA_TREASURY_SECRET_KEY`
- `IMGBB_API_KEY`
- `GEMINI_AI_API_KEY` (copied into Secret Manager as `GEMINI_API_KEY`)
- `FIREBASE_SERVICE_ACCOUNT_TRANYX_APP`

`requestWithdrawal`, `reconcileWithdrawals`, and `staffOps` read `SOLANA_TREASURY_SECRET_KEY`. `uploadImageProxy` reads `IMGBB_API_KEY`. `geminiAssist` reads `GEMINI_API_KEY`. A GitHub secret is not visible to Cloud Functions until the workflow copies it. If any of those GitHub secrets is missing, the production job fails before deploy.

Params already named in `functions/.env.tranyx-app` (values stay in that file):

- `SOLANA_RPC_URL`
- `SOLANA_USDT_MINT`
- `ENFORCE_APP_CHECK`

Confirm `ENFORCE_APP_CHECK` is `true`. Leave it true. `SOLANA_TREASURY_PUBLIC_KEY` stays unset so withdrawals keep reading `system_config/treasury`.

## 2. Staff claims by email

Source of truth: `users` on `tranyx-admin-portal` where `isAdmin`, `isStaff`, or `isSuperAdmin` is true. That project is separate from `tranyx-app`, so an admin-portal uid is not a tranyx-app uid. The tool uses the email on the user document, or admin-portal Auth when that email is empty, then finds the tranyx-app user with `getUserByEmail` and grants claims on the tranyx-app uid. It does not grant a uid that is missing from tranyx-app Auth. Unmatched people are printed with `email` and `reason` (`no-email` or `no-target-user`).

Admin and superadmin get `{ admin: true, role: 'admin' }`. Staff-only get `{ admin: false, role: 'staff' }`.

Do not pass `--revoke` for this release. Revocation, when you do pass it, looks at tranyx-app Auth users who still have admin or staff claims and were not matched by email.

```bash
cd ~/Desktop/tranyx_workspace
node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod
node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply
```

The first command only prints `grant`, `unmatched`, and `wouldRevoke`. The second writes claims on the matched tranyx-app uids and logs each `setCustomUserClaims`. Running it again skips users whose claims already match.

Each staff and admin person signs out of the web app and signs back in. An existing ID token keeps the old claims until then.

## 3. Public profile backfill

After the rules deploy, clients can no longer read another person's `users/{uid}`. Counterparties need `public_profiles/{uid}` first. The rules deploy in the same job as the functions, so this backfill runs before the `main` push. The tool copies only the public card (name, photo, headline, skills, rating, and the other allowlisted fields). It does not copy email, phone, wallet, balances, KYC, or `idVerified`.

```bash
cd ~/Desktop/tranyx_workspace
node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod
node tool/backfill_public_profiles.mjs --project tranyx-app --allow-prod --apply
```

Dry-run prints uids and field names. Apply logs each `set`. A second apply skips cards that already match.

## 4. Push main: functions, rules, indexes, then hosting

Branch protection in `.github/workflows/ruleset.yml`:

- `uat` accepts a merge only from `develop`
- `main` accepts a merge only from `uat`

Do this only after steps 2 and 3. One push to `main` runs **Deploy hosting and production functions** (`.github/workflows/jaspr-hosting-merge.yml`). On `main`, that job does these in order:

1. `firebase functions:secrets:set` for `SOLANA_TREASURY_SECRET_KEY`, `IMGBB_API_KEY`, and `GEMINI_API_KEY` (from GitHub secret `GEMINI_AI_API_KEY`), reading stdin (`--data-file=-`). It does not print the values.
2. `firebase deploy --only functions,firestore:rules,firestore:indexes --project tranyx-app`.
3. Hosting channel `live` on the default site `tranyx-app` when web files changed. Live URLs: https://tranyx-app.web.app and https://tranyx.app.

Dev and UAT pushes still deploy only their own hosting projects. They do not deploy functions or rules. A push to `main` does not publish mobile.

```bash
cd ~/Desktop/tranyx_workspace
git fetch origin
git checkout uat
git pull origin uat
git merge origin/develop
git push origin uat

git checkout main
git pull origin main
git merge origin/uat
git push origin main
```

Wait until the GitHub job is green. The release is then live at https://tranyx.app.

Rules in that deploy:

- staff and admin money paths require the custom claims from step 2
- `users/{uid}` is readable by the owner or claim staff; other people use `public_profiles/{uid}`
- exact listing address and coordinates are not client-writable on the public job, property, or vehicle document
- `{jobs|properties|rentals}/{id}/private/location` is readable by any signed-in user

After the job succeeds, these commands show metadata only:

```bash
gcloud secrets describe SOLANA_TREASURY_SECRET_KEY --project tranyx-app
gcloud secrets describe IMGBB_API_KEY --project tranyx-app
gcloud secrets describe GEMINI_API_KEY --project tranyx-app
gcloud secrets versions list SOLANA_TREASURY_SECRET_KEY --project tranyx-app
gcloud secrets versions list IMGBB_API_KEY --project tranyx-app
gcloud secrets versions list GEMINI_API_KEY --project tranyx-app
```

Do not run `firebase functions:secrets:get` or `gcloud secrets versions access`.

There is no laptop fallback for this deploy. If you ever rebuild the web by hand, pass only public defines:

```bash
cd ~/Desktop/tranyx_workspace/packages/tranyx_web
jaspr build --dart-define=ENV=prod \
  --dart-define=BASEMAPS_API_KEY="$BASEMAPS_API_KEY" \
  --dart-define=SOLANA_PUBLIC_KEY="$SOLANA_PUBLIC_KEY"
```

Do not pass `XENDIT_SECRET_KEY`, `IMGBB_API_KEY`, `GEMINI_AI_API_KEY`, or `CLOUDFLARE_API_TOKEN`. `ENV=prod` bakes in the reCAPTCHA Enterprise site key and `ReCaptchaEnterpriseProvider`. Do not pass `APPCHECK_SITE_KEY`. Do not use the old `6LfRz...` key.

## 5. Listing addresses, then completion codes

Run these only after the new web and the new rules are both live. The new client reads exact coordinates from `private/location`. Moving them earlier hides addresses from the previous web.

```bash
cd ~/Desktop/tranyx_workspace
node tool/migrate_listing_locations.mjs --project tranyx-app --allow-prod
node tool/migrate_listing_locations.mjs --project tranyx-app --allow-prod --apply

node tool/purge_job_completion_codes.mjs --project tranyx-app --allow-prod
node tool/purge_job_completion_codes.mjs --project tranyx-app --allow-prod --apply
```

Dry-run lists document ids and field names. It does not print street addresses or completion codes. Apply logs every `set` and `update`. A second apply skips documents that are already migrated or already purged.

## 6. Smoke test

Use a real signed-in account and a staff account that has signed out and back in since step 2.

- **Guest (signed out).** Open a job, a property, and a vehicle. The address reads `Brgy. *****, ****`. The map control does not open a map.
- **Signed-in user.** Open the same three listings. The full address and the map are visible. Open another person's profile card and confirm it has no email, phone, wallet, or balance.
- **Staff.** Sign out and back in. Open a staff money screen and confirm it loads. Do not approve your own deposit or withdrawal.
- **Admin.** With an `admin` claim, open a staff-only user lookup that a normal account cannot list.
- **Deposit.** Send one small on-chain deposit from a verified wallet. Confirm the balance increases once. Refresh and confirm it does not increase again for the same signature.
- **Withdrawal.** Request one Solana withdrawal at the configured minimum (`config/withdrawals.minPhp`, default 100 PHP). Confirm one debit and no second debit if you retry the same action.

## 7. Rollback

Revert the release commit on `main` and push. That runs the same workflow again: it rewrites the Secret Manager versions from the GitHub secrets, then deploys the previous functions, rules, indexes, and hosting. Do not delete functions.

Hosting only, from a machine that is already logged into `tranyx-app`:

```bash
npx firebase-tools@15.5.1 hosting:releases:list --project tranyx-app
npx firebase-tools@15.5.1 hosting:rollback --project tranyx-app
```

Data migrations are not reversed by a redeploy. Restoring a public street address or a completion code means restoring those fields from a backup. Do not run a second `--apply` as a rollback; a second apply is a no-op on already migrated documents.

Claims are not removed by a rollback. Leave them in place unless you intentionally run:

```bash
cd ~/Desktop/tranyx_workspace
node tool/sync_staff_claims.mjs --project tranyx-app --allow-prod --apply --revoke
```
