# Money-field rules lock: deploy order and client blockers

Branch `fix/rules-lock-money-fields`, two commits. Rules are built with the no-mirror build (`firestore.rules` regenerated from `firestore_rules/*.rules`).

## Commit 1: premium / subscription fields and on-chain markers (safe once Phase 1 clients ship)
- Owners can no longer write `subscriptionPlan|StartedAt|PaymentMethod|PaymentAmount|TxId|Status`, and can only move `isPremium`, `premiumUntil` and `accountType` DOWN (expiry downgrade). New profiles cannot be created premium/hybrid.
- `deposit_sol_*`, `deposit_usdt_*`, `sub_sol_*` and `onchain_*` transactions: create and update are staff / Admin SDK only. `onchain_<sig>` is no longer world-readable.
- Still owner-writable: `pendingSubscription`, `lastSubscriptionRejection`, `updatedAt`, `pending_onchain_<uid>_<sig>`.
- Requires: `creditOnchainPayment` deployed and the Phase 1 mobile/web builds live. Old clients can no longer credit on-chain payments.
- Balance-paid subscription now goes through the `subscribeWithBalance` callable (web `processTyxbitSubscriptionPayment`). Mobile only downgrades on expiry (`updatePremiumStatus`), which the rules still allow. No client blocker left for this commit.

## Commit 2: `tyxBalance` / `reservedBalance` (phase 4: all legitimate client flows are callables now)
Branch `feat/fn-booking-charge` moves every owner/counterparty balance write for rentals, jobs, subscriptions and P2P cancel into server callables (Admin SDK). The escrow collections (`rental_escrows`, `rental_extension_escrows`, `property_escrows`, `escrow`, `escrow_holdbacks`) are now Admin-SDK / staff only in the rules, so a client can neither mint an escrow nor flip one to Refunded / Released.

Callables (all: idempotencyKey, Firestore transaction, amounts and fees recomputed server-side, status guards so a refund / release happens once, generic client errors, `ENFORCE_APP_CHECK`)
- `subscribeWithBalance` (price from `config/credit`)
- `bookingRequest` (vehicle + property): hold = price + fee (+ deposit) from the listing doc, `settings/platform_fees` and `promos/{code}`
- `bookingAction`: `reject`, `revoke`, `cancelRequest`, `cancelActive` (refund minus the 2.00 fee), `complete` (host payout, commission, property deposit refund)
- `rentalExtension`: `request`, `autoApprove`, `approve`, `reject`
- `listingFee`: `charge` / `refund` (record in `listing_fees/{kind}_{id}`)
- `jobAction`: `create`, `accept` (counter-offer difference), `complete`, `cancel`, `reclaim`, `delete`, `releaseHoldbacks`
- `updateP2pWithdrawal` (owner cancel + refund, already in the withdrawal phase) is now used by web and mobile too

Client flows switched (web `firebase_service.dart` / `tranyx_app.dart`, mobile `transit_repository.dart` / `job_repository.dart`)
- vehicle + property: request, approve (escrow dual-write removed), reject, cancel request, revoke, cancel active, complete, extension request / auto-approve / approve / reject, listing fee charge + refund
- jobs: post (create + escrow), hire incl. counter offer, complete (code scan and QR), cancel, reclaim, delete, holdback release
- balance-paid subscription, P2P cashout cancel
- removed: web `updateTyxBalance`, `deductTyxBalanceSafely`, dead `bookRental`; mobile `updateTyxBalance`, unused `depositFunds`; `reconcilePendingEscrows` is a no-op

What is still a client balance write (all staff / agent only; allowed by `isAdminOrStaff()`, which includes `isP2pAgent`)
- web: `resolveDispute` (3 variants), `adminOverrideCancelJob`, `approveDepositRequest`, `rejectP2pWithdrawalOrder`
- mobile: `adminOverrideCancelJob`, `approveDepositRequest` (`transit_repository.dart` ~2676-2700)
- Admin portal staff writes (`withdrawals`, `disputes`, `deposits`, `subscriptions`), unchanged
- Follow-ups worth doing before public launch: move these into staff callables; `isP2pAgent` currently lets an agent write any user's balance from a client; `rental_requests` / `property_requests` `status` is still client-writable (only money fields and escrows are protected).
- `adminOverrideCancelJob` / `resolveDispute` refund only the escrow `amount`, not the pre-funded employer fees (old behaviour, unchanged).

Legacy escrows: `RefundPending` escrows created by old clients can no longer be self-claimed (the escrow docs are not client writable). Staff / a one-off script must settle any that exist at cutover.

Other things the grep turned up but this branch does not change
- `transactions/*` ledger docs are still owner-creatable with a client-chosen `type` (only payout / rebate / fee_deduction and structured ids are restricted). Nothing server-side should trust them as proof of payment.
- `deposit_requests`, `subscriptions` and `users/{uid}/ledger|transactions|points` are owner-writable.
- `wallets/{uid}.balance` is owner-writable but nothing reads it as money.

## Deploy order
1. Deploy Cloud Functions (`creditOnchainPayment`, withdrawal + payout, `subscribeWithBalance`, `bookingRequest`, `bookingAction`, `rentalExtension`, `listingFee`, `jobAction`) to the project. Needs Blaze.
2. Ship the mobile and web builds that call them.
3. Deploy rules commit 1.
4. Settle any legacy `RefundPending` escrows, then deploy rules commit 2 (tyxBalance lock + escrow collections Admin-SDK only). Old app builds still writing escrows or balances will fail after this step.

## Wallet-verified deposits (fix/wallet-verified-deposits)

`creditOnchainPayment` now credits only a wallet with an Admin-only `wallet_verified/{wallet}` record bound to the caller's uid (written by `walletAuthLink` after a signed challenge). Otherwise it throws `failed-precondition` with a message starting `WALLET_NOT_VERIFIED` and leaves the pending record open (the same signature credits after verification). `walletAuthStatus` tells a client whether its wallet is proven.

- Web: Profile shows "Verify wallet" for an unproven wallet; deposits/subscriptions verify first (`_ensureVerifiedWalletLink`).
- Mobile: MWA wallets sign the challenge in-app (`wallet_verify.dart`, `MwaService.signMessage`) before paying. Phantom / Trust deep-link wallets cannot sign messages from the app yet, so they are told to verify once on tranyx.app > Profile. The MWA `signMessages` call is unit-tested against a fake only; it needs a device check.
- Not tightened: client writes to `walletLinks/*` and `users.walletPublicKey`. Shipped mobile builds link wallets by writing those directly (app_router, auth_provider, trust_pane, payment_pane, subscription_pane, mwa_wallet_link). They are harmless to money now (credit trusts `wallet_verified` only), so locking them waits until mobile links through `walletAuthLink` and old builds age out.
- Existing users with a wallet linked before this change must verify once before their next deposit.

## Public-release blockers (fix/rules-release-blockers)

### (b) Job `completionCode` is no longer on the public job doc
- `jobs` is world-readable, so the code used to be readable by anyone (and a worker could write it themselves). Now the server owns it.
- New `jobAction` action `generateCode`: the party who must hand the code over (employer; the worker when the gig has a tracker) calls it and gets `{code}` back. The code lives in `job_secrets/{jobId}` (Admin SDK only; the rules deny every client read and write). Calling it again returns the same code until it is used or locked. The verifier never receives it.
- `complete` reads the code from `job_secrets` (legacy fallback: `completionCode` / `verificationCode` on the job doc, so gigs issued by old clients still finish). Success deletes the secret. 5 wrong codes lock the gig (`CODE_LOCKED`) until the other party generates a fresh code (counter reset).
- Rules: `completionCode` removed from the employer and worker update field lists; `job_secrets/*` explicitly denied.
- Clients: web `generateCompletionCode` and mobile `JobRepository.generateCompletionCode` call the callable; the client-side code comparison is gone (the server verifies).
- Zeus / ops: gigs created before this deploy still show their legacy `completionCode` on the public job doc until someone calls `generateCode` on them (that call deletes the field). To purge them all, run once with the Admin SDK: for every `jobs` doc with status not in (Completed, Cancelled) and a `completionCode`/`verificationCode`, `update({completionCode: FieldValue.delete(), verificationCode: FieldValue.delete()})`. Old app builds that still write the code will now be denied by the rules.
- Deploy order: functions first, then clients, then the rules (otherwise "Generate code" fails).

### (a) `rental_requests` / `property_requests` status is no longer freely client-writable
- Clients cannot create or delete request docs (the `bookingRequest` callable does). Updates must come from a party (renter / host on the doc), cannot touch identity or money fields (`renteeId`, `renterId`, `hostId`, `bookingFee`, `discountAmount`, `promoCode`, deposit / commission / platform fee fields, `createdAt`), and may only make these status moves: host `Pending -> Approved`, renter `Approved | Awaiting Signature -> Booked`, other open states (e.g. `Active`) but never back to `Pending` / `Approved` / `Booked`.
- `Rejected` / `Cancelled` / `Completed` / `Refunded` can be written by a client only while no escrow is `Held` (legacy no-escrow requests). With funds held, only `bookingAction` closes a request. Reason: the callable refuses to settle a request that is already closed, so a party could previously park a funded booking in a closed state and lock the money. Writes that leave `status` unchanged (the clients echo the status after the callable) stay allowed.
- Server: `bookingAction complete` now also refuses `Approved` / `Awaiting Signature` (an unsigned booking can't pay out the host).
- Still true: `rental_requests` / `property_requests` read is open to any signed-in user (needs a read-scope change plus the owner/host queries re-checked; not done here).

### (c) isP2pAgent / staff client balance writes (NOT done in this branch)
`isAdminOrStaff()` includes `isP2pAgent`, so an agent can still write any user's `tyxBalance` from a client (web `resolveDispute`, `adminOverrideCancelJob`, `approveDepositRequest`, `rejectP2pWithdrawalOrder`; mobile `adminOverrideCancelJob`, `approveDepositRequest`). Plan: staff callables (`staffSettleDispute`, `staffCancelJob`, `staffApproveDeposit`, `staffRejectWithdrawal`) with a staff / agent check, idempotency keys, the transaction ledger plus an `audit_logs` entry, then drop the user `tyxBalance` write from the `isAdminOrStaff()` rule for agents. Needs the admin portal rules mirror, so it should be its own branch and release.
