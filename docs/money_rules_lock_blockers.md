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

### (c) isP2pAgent / staff client balance writes (feat/fn-staff-balance-ops)
Callable `staffOps` (functions/src/staff_ops.ts), one Firestore transaction per action, idempotencyKey, status guards, and an Admin-SDK-only `staff_audit_log/{uid_key}` entry (actor, role, ids, amounts, balance before / after):
- `claimWithdrawal` / `releaseClaim` / `rejectWithdrawal` (P2P cashouts; reject refunds `balanceDeducted` funds once, guarded on status). TRAD-12: the claim accepts the statuses the queue shows as "waiting" (`WAITING_FOR_AGENT`, `PENDING_REVIEW`, `REQUESTED`, `OPEN`, `PENDING`); the old admin-portal check only accepted four of them, so a `PENDING_REVIEW` order was reported as "no longer available, handled by another agent". Concurrent claims serialise on the transaction; a second agent gets `CLAIMED_BY_OTHER`.
- `approveDeposit` (manual P2P deposits): amount and owner from `deposit_requests`, reference registered in `claimed_p2p_references`, credit once.
- `resolveDispute` (admin / staff only): parties and amount from `escrow/{jobId}` + `jobs/{jobId}` (the dispute doc is client-created and untrusted), `REFUND_EMPLOYER | PAY_NYXIAN | SPLIT_ESCROW`, escrow must be `held`.
- Roles: server-issued custom claims only (`staffClaimsOnly()`). Legacy users-doc flags and an active `p2p_agents` doc grant `staffOps` only inside the Functions emulator when `STAFF_CLAIMS_ONLY=false`. A deployed function ignores that off switch.
- Rules (separate commit): staff / agents (everything under `isAdminOrStaff()`) can no longer write `tyxBalance` / `reservedBalance` on `users`, nor create a profile with a balance. This also closes the KNOWN-HOLE ESC-02 / ESC-10 / ESC-14 tests.
- **Deploy order**: functions, then the admin panel build that calls `staffOps`, then this rules commit. The in-app staff tools in the workspace clients still write balances directly and will fail after the rules commit: web `resolveDispute` (3 variants), `adminOverrideCancelJob`, `approveDepositRequest`, `rejectP2pWithdrawalOrder`, mobile `adminOverrideCancelJob`, `approveDepositRequest`. Migrate them to `staffOps` (or retire them in favour of the admin panel) before deploying the rules.
- Not done: the admin panel's `syncEnvAuth` still self-writes `users/{uid}` (`isAdmin`, `isP2pAgent`) and `p2p_agents/{uid}` for the signed-in staff member. Those flags no longer grant `staffOps` and can no longer write privilege or premium fields (see the security-foundation section). `isUserAdminInDoc` / `isP2pAgentInDoc` still open the rest of `isAdminOrStaff()` (desk reads, moderation). Replace that with custom claims before treating doc flags as dead.

## Security foundation (privilege, self-money, premium, audit, payout wallet)

Nothing here was deployed. Rules are compiled from `firestore_rules/*.rules` into `firestore.rules` only (no admin-repo mirror).

- Privilege fields on `users` (`role`, `admin`, `isAdmin`, `isStaff`, `isSuperAdmin`, `isP2pAgent`) can be created or updated only by `isClaimAdmin()` (custom claims `admin` / `superadmin` / role admin). An active `p2p_agents` doc, a users-doc flag, and a `role=agent|staff` claim cannot set them, including `set` merge and field removal. Ordinary signup (no privilege keys, zero balance, not premium) stays allowed. This patch does not mint claims or provision admins.
- `approveDeposit`, `claimWithdrawal`, and `rejectWithdrawal` refuse when any owner alias (`uid`, `userId`, `user_id`, `ownerId`, `ownerUid`, `owner`, `accountId`, `accountUid`, `walletOwnerId`, including a `users/` or `wallets/` prefix and surrounding whitespace) is the caller. Disagreeing aliases are `OWNER_MISMATCH` and credit nobody. The rejection writes no balance, audit, or idempotency record. Cross-user agent operations and admin actions on someone else's money stay. `releaseClaim` is not a money movement.
- `isPremium` / `premiumUntil` / subscription fields on `users`, and the same entitlement plus privilege fields on `wallets/{uid}`, are claim-admin writes. Agents cannot create, update, or delete another user's wallet to plant them. Owners can still downgrade their own user premium.
- `staff_audit_log` reads require `isClaimAdmin()`. Clients still cannot write it.
- Staff idempotency stores actor, action, and target. The same tuple replays the stored result (including concurrent retries). A different action or target returns `IDEMPOTENCY_MISMATCH` and does not run the other money action. Another actor does not receive the stored result.
- Solana payout destination is `users.walletPublicKey` only when `wallet_verified/{wallet}.uid` is the caller (`walletAuthLink`). `solanaWalletAddress` / `walletAddress` must match that key or the call is `WALLET_MISMATCH`. A base58 check is not authorization. The request stores that verified address; `executeSend` pays the stored address. No new approval cap or fee.

### Admin project vs workspace project (App Check)

`tranyx-app` is the production Firebase project for public web and mobile. `tranyx-dev` and `tranyx-uat` are the other workspace projects. `tranyx-admin` is a separate Firebase project used by the admin client; it is connected to those workspace projects and is not one of them. App Check and Auth tokens are project-scoped. Registering the admin app, or holding an admin-project App Check token, does not make that token valid for the workspace project the desk has selected. Callables keep `ENFORCE_APP_CHECK` defaulting on and do not treat an admin UI session as a substitute for the selected project's Auth token and App Check token. Prod is registered only as the prod workspace project among prod / dev / UAT. This patch does not change live App Check config.

### Web staff money calls (not deployed)

`approveDepositRequest`, `rejectP2pWithdrawalOrder`, `resolveDispute`, and `adminOverrideCancelJob` call `staffOps`. They no longer write balances, escrow, or money statuses from the browser. `adminCancelJob` refunds a held escrow `amount` only (not employer fees) and sets the gig `ADMIN_CANCELLED`. A missing escrow is not invented from the job price. `PENDING_VERIFICATION` is an approve-able deposit status because that is the status the web proof step already writes. Split disputes with no percents still send 50/50, the previous client default.

Claim provisioning, later, by an owner with the Admin SDK (this repo does not mint claims):

- `admin` / `superadmin` (or `role` admin) to read `system_config`, write `p2p_agents`, and edit privilege fields.
- `role` admin or staff for `resolveDispute` and `adminCancelJob`. `role` agent may claim and record payout proof, and may `approveDeposit` / `rejectWithdrawal`, but cannot client-approve or client-reject a withdrawal and cannot read treasury.
- A `users` flag or an active `p2p_agents` doc does not grant any of that.

## Still open (next release-blocker batches, not in this patch)

- No `staffOps` action for proof, finalize, or manual payout completion. Web still writes those itself: `FirebaseService.submitWithdrawalProof` and `confirmP2pWithdrawalCompleted`. Claim staff may still record a claim or proof on `withdrawal_requests`; approve, reject, and the balance stay on `staffOps`.
- `rental_requests` and `property_requests` are readable by a party (`hostId`, `renteeId`, `renterId`, `uid`, `userId`) or `isClaimStaff()`. Listing-id-only queries (`getAllRequestsForVehicle`, `getPendingRequestsForVehicle`, `getAllRequestsForProperty`, `getPropertyPendingRequestsForProperty`) are denied until they also filter a party field. `/rentals` and `/properties` stay public.
- `users.terraPoints` cannot be raised by the owner or a doc-flag staff write. `awardPointsIfEligible` still attempts that client write and will be denied until a server grant exists. An admin custom claim, or the Admin SDK, can set the field.
- `isAdminOrStaff()` still trusts users-doc flags for non-money desk access (support chats, moderation). It does not authorize treasury reads, `p2p_agents` writes, withdrawal approval, escrow money fields, or booking-request reads.
