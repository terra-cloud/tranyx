# Tranyx Cloud Functions

## `creditOnchainPayment` (callable v2, App Check enforced)

Server-side crediting of on-chain payments. Replaces the client-side marker transactions in the
mobile (Firestore SDK) and web (REST) apps.

Client sends **only** `{ signature, kind: 'deposit_sol' | 'deposit_usdt' | 'subscription_sol', plan?: 'monthly' | 'yearly' }`.
Amounts, wallets, rates and marker ids from the client are never read.

1. Cheap replay answer from `transactions/onchain_<sig>` (no RPC).
2. Per-uid attempt budget (`credit_usage/{uid}_{hour}`, default 30/h) so the callable cannot burn RPC quota.
3. The caller's `users/{uid}.walletPublicKey` must be a valid key, and `walletLinks/<key>` (if present) must name the caller.
4. `getTransaction` (`jsonParsed`, **finalized**) from the project's cluster. Not finalized yet -> `{status:'not_finalized'}` (clients poll).
5. Verification: tx succeeded; the linked wallet **signed**; SOL = sum of system transfers wallet -> treasury;
   USDT = spl-token `transfer`/`transferChecked` with authority = wallet to the treasury's ATA for the project's USDT mint
   (`transferChecked` must also name the mint).
6. PHP value = on-chain amount x **server-side rate** (CoinGecko, then Binance SOLUSDT x open.er-api USD/PHP: the same sources
   the apps used, `src/rates.ts`), floored to centavos, sanity-banded. Deposits credit what was actually paid.
   Subscriptions: paid value must be >= plan price x (1 - 5%) (monthly 299, yearly 2999).
7. ONE Admin SDK transaction: read `onchain_<sig>`, per-flow marker, user, pending; if either marker exists ->
   `already_processed` (same uid) or `held_by_another_account` (note left on the caller's pending record); otherwise
   `tyxBalance += php` (or extend `premiumUntil` from `max(now, premiumUntil)` + plan fields), `create` the per-flow marker
   (`deposit_sol_<sig>`, `deposit_usdt_<sig>`, `sub_sol_<sig>`), `create` `onchain_<sig>` with exactly
   `{uid,type:'onchain_marker',solanaTxSignature,markerId,markedAt}`, and close `pending_onchain_<uid>_<sig>`.
   `solanaTxSignature` and `markerId` are derived from the verified signature, so the id/field consistency is enforced here.

Result: `{ status: credited | already_processed | held_by_another_account | not_finalized | rejected, reason?, phpAmount?, ... }`.
`reason` is a fixed code (`NOT_SIGNED_BY_LINKED_WALLET`, `NO_MATCHING_TRANSFER`, `TX_FAILED`, ...); internal detail stays in logs.

Optional `config/credit` (admin-only): `enabled` (kill switch, default true), `minPhp`, `maxPhp`, `planTolerance`,
`monthlyPhp`, `yearlyPhp`, `hourlyAttempts`, rate bands.

### Params (non-secret) in `functions/.env.<projectId>`

| project | `SOLANA_RPC_URL` | `SOLANA_USDT_MINT` |
|---|---|---|
| tranyx-dev | devnet | Circle USDC devnet proxy (same stand-in the app uses) |
| tranyx-uat | testnet | mainnet USDT mint (no official testnet USDT; same fallback the app uses) |
| tranyx-app | mainnet-beta | mainnet USDT |

`SOLANA_TREASURY_PUBLIC_KEY` (public key only; optional) - when empty the function reads `system_config/treasury`
(`publicKey`). The treasury **secret** is not used by this function. Public RPC endpoints are rate limited:
use a dedicated provider for UAT/prod and keep its URL out of git (functions params / `.env.local`).

### Known residual risk
`creditOnchainPayment` still checks the payer against `users.walletPublicKey` / `walletLinks`, which a client can write
without proof. `wallet_verified/{wallet}` (written by `walletAuthLink`) is now the proven source: make the credit require it
once existing users have re-linked with a signature (decision pending).

## Sign-In With Solana (`walletAuthNonce`, `walletAuthSignIn`, `walletAuthLink`)

Wallet sign-in was removed in KAN-124 because it trusted `walletLinks` (client-writable). It returns here with a
signature proof, and only these callables (Admin SDK) can mint a Firebase custom token.

1. `walletAuthNonce({ wallet, purpose: 'signin' | 'link' })` -> `{ nonce, message, expiresAt }`. The message is a plain-text
   SIWS-style challenge naming the domain (taken from the request `Origin`, which must be in `WALLET_AUTH_DOMAINS`), wallet,
   nonce and a 5 min expiry. Stored in `wallet_auth_nonces/{nonce}`; single use.
2. The wallet signs the message (`signMessage`). The client sends the signature as base58 or base64.
3. `walletAuthSignIn({ wallet, nonce, signature })` verifies ed25519 server-side, then returns
   - `{ status: 'signed_in', customToken }` when `wallet_verified/{wallet}` names an active, non-staff account,
   - `{ status: 'needs_signup', ticket }` when the wallet is unknown (go to account creation, email + password required),
   - `{ status: 'rejected', reason }` (`BAD_SIGNATURE`, `WALLET_LINK_UNVERIFIED`, `ACCOUNT_BLOCKED`, `STAFF_ACCOUNT`).
4. `walletAuthLink({ ticket } | { wallet, nonce, signature })` (signed in) links a PROVEN wallet to the caller, one wallet per
   account in both directions. It writes `walletLinks/{wallet}`, `users/{uid}.walletPublicKey` and the Admin-only
   `wallet_verified/{wallet}`. A wallet already proven by another account is refused. An unproven `walletLinks` entry
   (client-written squat) is replaced by the key holder's proof.

`walletLinks` stays a client-writable index and is never trusted for sign-in: only `wallet_verified` is. Existing links
made before this change are unverified: those users sign in with email and re-link once (a signature) from Profile.
Param `WALLET_AUTH_DOMAINS` (default `tranyx.app,dev.tranyx.app,uat.tranyx.app,localhost`): trim per project, e.g. drop
`localhost` in prod. Email/password credentials come from the normal sign-up (the account is a normal Firebase user), so the
user can sign in with either.

## Tests
```
npm test            # tsc + emulator tests (Firestore emulator on 8189; never 8080/8199)
npm run test:e2e    # Auth + Firestore + Functions emulators, real callable over HTTP (App Check on and off), mocked chain/rates
```
Nothing here deploys or touches a real project. Do not deploy functions without a Blaze plan decision.
# Tranyx Cloud Functions (KAN-146)

Server-side withdrawals. The Solana **treasury secret key exists only in Firebase Secret Manager**
(`SOLANA_TREASURY_SECRET_KEY`). It is not in the web/mobile builds, `env.g.dart`, `generate_env`, CI
or Firestore.

| Function | Trigger | Purpose |
|---|---|---|
| `requestWithdrawal` | callable (v2, App Check enforced) | Solana (SOL/USDT) and P2P (GCash/Maya) withdrawals |
| `reconcileWithdrawals` | scheduler, every 5 min | settles in-flight transfers from on-chain truth |

## How a withdrawal works

Client sends only `{ idempotencyKey (uuid v4), method: 'solana'|'p2p', amount, coin | p2p{...} }`.
Everything else (fee, net, rate, crypto amount, destination wallet = the wallet linked on the profile,
balance) is read or computed on the server. Order of operations: **checks -> effects -> interaction**.

1. One Firestore transaction: auth/ban/active-rental checks, min/max, available balance
   (`tyxBalance - reservedBalance`), per-user daily limits, fee, **debit `tyxBalance`**, create
   `withdrawal_requests/{idempotencyKey}` (+ mirror `withdrawalRequests/{key}`) with
   `payoutState: 'pending'`, and the ledger rows. Two concurrent calls cannot both pass the balance check.
2. Only after commit, Solana only: build + sign the tx, persist `solanaTxSignature` +
   `lastValidBlockHeight` (`payoutState: 'submitting'`), then broadcast.
3. `sent` on confirmation. Ambiguous result (timeout etc.) -> `pending_confirmation`, **no refund**.
   Refund + `failed` happens only when the chain says the tx failed, or it never landed and the
   blockhash expired; the refund is a transaction guarded on `payoutState`, so it can happen once.
   The reconciler (and any idempotent retry) re-checks `getSignatureStatuses`.

```
pending -> submitting -> sent
              \-> pending_confirmation -> sent | failed(refunded once)
```

P2P: debit + request (`status: WAITING_FOR_AGENT`, `payoutState: manual_review`, fee `p2pFeeRate`, default 0),
agent notification; staff/agents process it exactly as before. Cancel/confirm by the owner are unchanged.

Retrying with the **same** idempotency key returns the existing record and never pays twice. A retry
after a definitive failure needs a new key (the apps do this).

## Config (`config/withdrawals`, optional, admin-only in rules)

`walletCooldownHours` (default 24; 0 disables), `enabled` (**kill switch, OFF by default**: withdrawals, Solana and P2P, are rejected until staff create
`config/withdrawals` with `enabled: true`; only the boolean `true` counts), `minPhp` 100, `maxPhp` 50,000, `dailyMaxCount` 3, `dailyMaxPhp` 100,000
(per user per Manila day), `solanaFeeRate` 0.02, `p2pFeeRate` 0, rate sanity bands
`usdtPhpMin/Max`, `solPhpMin/Max`. Defaults live in `src/config.ts`. Usage is tracked in
`withdrawal_usage/{uid}_{YYYY-MM-DD}` (server only).

Non-secret params in `.env.<projectId>`: `SOLANA_RPC_URL`, `SOLANA_USDT_MINT`, `ENFORCE_APP_CHECK`
(default true). Do not put an RPC URL that contains an API key in a committed file.

## Payout-wallet cooldown

`users/{uid}.walletPublicKey` is owner-writable, so the function keeps its own server-only record,
`payout_wallet_state/{uid}` = `{wallet, since}`. A Solana withdrawal is allowed only after the profile wallet has matched
that record for `walletCooldownHours` (default 24). Any wallet change restarts the clock; the first request after a change
(or the first request after this rolls out, for users with no record) records it and is refused with a clear message.
To avoid a one-time 24h wait for existing users, staff can pre-seed `payout_wallet_state/{uid}` with `since` in the past
(Admin SDK only; clients cannot read or write it).

## One-time setup per project (tranyx-dev first, then uat, then tranyx-app)

1. **Billing**: upgrade the project to Blaze, and add a budget + alerts (Console -> Billing -> Budgets & alerts).
2. **Secret**: `firebase functions:secrets:set SOLANA_TREASURY_SECRET_KEY --project <id>` and paste a
   **freshly generated** treasury key (base58 or JSON byte array). Fund that wallet. Do not reuse the old key.
3. **App Check**: Console -> App Check: register the web app (reCAPTCHA v3/Enterprise), copy the public
   site key into the GitHub repo *variable* `APPCHECK_SITE_KEY`; register the Android app (Play Integrity)
   and iOS app (App Attest/DeviceCheck); register debug tokens for debug builds.
   Escape hatch while rolling out: `ENFORCE_APP_CHECK=false` in `.env.<id>` (re-enable afterwards).
4. **Deploy order** (rules last, otherwise old clients that still write requests directly will break):
   `firebase deploy --only functions --project <id>`, then ship web/mobile builds, then
   `firebase deploy --only firestore:rules --project <id>`.
5. **Rotate the old key**: the previous treasury key was embedded in shipped client builds, so treat it as
   leaked. After step 4 moves funds to the new wallet: delete `SOLANA_PRIVATE_KEY` / `TREASURY_PRIVATE_KEY`
   from GitHub secrets, delete `system_config/treasury.privateKeyBase58` if it exists, and drain/retire the old wallet.
6. Update `SOLANA_PUBLIC_KEY` / `TREASURY_PUBLIC_KEY` (public, used for deposits) to the new wallet.

## Where the old treasury private key lives (rotate all of it)

The key was compiled into every client build, so treat it as public. Locations, as of `develop` before this branch:

1. **GitHub Actions secrets** `SOLANA_PRIVATE_KEY` and `TREASURY_PRIVATE_KEY` (repo `terra-cloud/tranyx`), injected into
   `.github/workflows/jaspr-hosting-merge.yml`, `jaspr-hosting-pull-request.yml` (web dev/uat/prod builds) and
   `tranyx-mobile-publish.yml` (Android/iOS builds). This branch removes them from the workflows; delete the secrets in repo settings.
2. **Shipped artifacts**: every web bundle deployed to hosting (dev/uat/prod) and every mobile build that was published carries it
   (`Env.solanaPrivateKey` -> `String.fromEnvironment`). Old builds stay extractable: rotating the wallet is the only fix.
3. **Developer machines**: any local `.env` / `packages/shared/lib/src/env.g.dart` (generated, git-ignored) that was generated with the key.
4. **Firestore**: check `system_config/treasury` for a `privateKeyBase58`/`privateKey` field (admin-only in rules, but remove it).
5. `.agents/memory/ledger_of_fixes_and_contracts.md` described the client-side signing (documentation only).

Rotation: generate a new keypair, `firebase functions:secrets:set SOLANA_TREASURY_SECRET_KEY --project <id>`, fund it, update
`SOLANA_PUBLIC_KEY`/`TREASURY_PUBLIC_KEY` (deposits) and `system_config/treasury`, sweep the old wallet to the new one, delete the
GitHub secrets, retire the old wallet. Nothing here ever prints or reads the key.

## Tests

```
npm test            # type-check + 30 tests (26 Firestore-emulator + 4 stubbed-RPC) (port 8189, never touches 8080)
npm run test:e2e    # Auth + Firestore + Functions emulators, real callable over HTTP (App Check on and off)
```
Emulator-only config: `../firebase.functions-test.json`. Nothing here deploys or touches a real project.
