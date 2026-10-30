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
`walletPublicKey` / `walletLinks` are linked without a signature proof, so "payer = linked wallet" is only as strong as the
link. Link a wallet with a signed message (sign-in-with-Solana) before treating this as hardened.

## Tests
```
npm test            # tsc + emulator tests (Firestore emulator on 8189; never 8080/8199)
npm run test:e2e    # Auth + Firestore + Functions emulators, real callable over HTTP (App Check on and off), mocked chain/rates
```
Nothing here deploys or touches a real project. Do not deploy functions without a Blaze plan decision.
