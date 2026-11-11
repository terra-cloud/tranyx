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
- Rules: `completionCode` removed from the employer and worker update field lists; `job_secrets/*` explicitly denied. Client create and update of `jobs` cannot add, change, or clear `completionCode` or `verificationCode`, including an `isAdminOrStaff()` client. A legacy field that is left untouched does not block other listing edits. `jobAction complete` deletes both fields after a successful check.
- Clients: web `generateCompletionCode` and mobile `JobRepository.generateCompletionCode` call the callable; the client-side code comparison is gone (the server verifies).
- Emulator-only purge: `functions/src/purge_job_codes.ts` and `tool/purge_job_completion_codes.mjs`. Dry-run is the default. `--apply` throws `REFUSING_LIVE_PURGE` unless `FIRESTORE_EMULATOR_HOST` is set, then deletes only those two fields and writes `purge_audit/job_codes_{at}`. `functions/test/purge_job_codes.spec.ts` covers dry-run, apply, and the live refusal on the Functions emulator. Do not point it at tranyx-dev, tranyx-uat, or tranyx-app.
- Residual production prerequisite: jobs created before this change can still hold `completionCode` / `verificationCode` on the public document. This patch does not clean live data. An owner has to run a reviewed Admin SDK delete of those two fields against the live project. Until then, `generateCode` and a successful `complete` remove the fields on the gigs they touch. `jobs` stays world-readable (PRV-01).
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

## Public profile and payout type strings

`users/{uid}` get is the owner or `isClaimStaff()`. List is `isClaimStaff()`. A signed-in stranger reads `public_profiles/{uid}` (get by id, no list). The owner may write only `uid`, `name`, `displayName`, `photoUrl`, `profile_photo`, `headline`, `about`, `accountType`, `skills`, `hourlyRate`, `businessName`, `industry`, `createdAt`, `updatedAt`, `rating`, `ratingCount`, and `isPremium`. `rating`, `ratingCount`, `isPremium`, and `accountType` must equal the user doc. Email, phone, wallet, balances, KYC, and `idVerified` are not on the public card. `idVerified` stays owner-writable on the private doc and is not copied. Web counterparty reads (`getPublicProfile` / `getPublicProfileMap`) use that card. Saving or loading your own user publishes it. Accounts that have not loaded since this change have no card until they do. No live backfill was run.

Booking requests no longer copy `users.idVerified` onto the request. Host verification text on a new request comes from the listing's own `hostIsVerified` / `hostVerificationStatus` / `hostVerificationTier`. The renter is recorded as unverified. The employer profile card no longer shows a phone number or verification badges.

Listing address, city, and map fields stay on the public job, property, and vehicle documents. PRV-01/02/03 require those documents to be readable. There is no separate private street field. PRV-12/13/14 still expect the whole document to be unreadable, which would remove discovery, so they stay expected failures.

`transactions` create rejects type strings `payout`, `payouts`, `rebate`, `rebates`, `fee_deduction`, `withdraw`, and `withdrawal` in any case. The same ban applies to creates on `users/{uid}/transactions`, `users/{uid}/ledger`, `wallets/{uid}/transactions`, and `wallets/{uid}/ledger`, and to an update that changes `type` into one of those values. `payout_nyx_` is not client-creatable except the hired-worker stopgap (type exactly `payout`, amount bound to the job) and an `isAdminOrStaff()` client writing type exactly `payout`. `fee` and `payment` on a `payout_nyx_` id are denied. Those two labels stay allowed on ordinary ids because existing clients already use them there. Party creates of `refund_job_`, `refund_stale_job_`, `refund_prop_`, `fees_emp_`, and `p2p_` stay. Staff can still create `deposit_sol_` / `deposit_usdt_` / `sub_sol_` / `onchain_` markers. Owners cannot. Server `jobAction` / `staffOps` ledger writes are Admin SDK and are unchanged. Withdrawal proof, finalize, and manual payout creation are still the next batch.

`feat/fn-booking-charge` is already an ancestor of this branch. `fix/wallet-verified-deposits` is already merged (PR 93). Neither branch was merged again.

## Withdrawal lifecycle

Owner cancel and confirm are `updateP2pWithdrawal` (`action: 'cancel' | 'confirm'`). The caller must be the withdrawal owner. No staff claim is required. Cancel refunds `amount` once, only from `WAITING_FOR_AGENT`, `PENDING_REVIEW`, or `PENDING`, and only when `balanceDeducted` is true. Confirm moves `PENDING_CONFIRMATION` to `APPROVED` only when `referenceNumber` is set and `proofImageUrl` is https. It does not debit, credit, or send. Disagreeing owner aliases return `failed-precondition` / `OWNER_MISMATCH` and write nothing. A second confirm returns `alreadyDone`.

`staffOps` `submitWithdrawalProof` is the claim holder only (`admin`, `staff`, or `agent` custom claim). Body: `withdrawalId`, `referenceNumber`, `proofImageUrl` (https). It sets `PENDING_CONFIRMATION` and does not change the balance or treat the image as a chain payment (`verifiedPayment: false`). A settled cashout returns `SETTLED`. A different proof after the first returns `PROOF_FROZEN`. Another agent's claim returns `CLAIMED_BY_OTHER`. The owner is `SELF_ACTION`. Same idempotency key used for a different action returns `IDEMPOTENCY_MISMATCH`.

`staffOps` `createManualWithdrawal` is `admin` or `staff` only. Body: `targetUserId`, `method: 'solana'`, `amount`, `coin: 'SOL' | 'USDT'`, UUID `idempotencyKey`. Optional `uid` / `userId` / `ownerId` must be the same person. It calls `processWithdrawal` for that person: server fee, `wallet_verified` destination, one debit, then the existing Solana send. P2P is refused. Self-target is `SELF_ACTION`. An agent is `permission-denied`. There is no staff action that marks a P2P cashout paid. Owner confirm is the only P2P settlement. Solana settlement stays `executeSend` / `reconcileWithdrawals`.

Web `agentClaimP2pWithdrawal`, `submitWithdrawalProof`, and `confirmP2pWithdrawalCompleted` call those functions. `cancelP2pWithdrawalRequest` already did. `handleWithdrawTyx` calls `requestWithdrawal` instead of writing `withdrawalRequests`. Client updates of `withdrawal_requests` and `withdrawalRequests` are denied. `payout_nyx_` and `deposit_sol_` / `deposit_usdt_` / `sub_sol_` / `onchain_` are not client-writable, including `isAdminOrStaff()`. `jobAction complete` and `creditOnchainPayment` still write them with the Admin SDK.

Admin client (separate repo, selected workspace Auth and App Check, not a central-project token):

| Action | Callable | Request | Success | Errors |
| --- | --- | --- | --- | --- |
| Claim | `staffOps` | `action: claimWithdrawal`, `withdrawalId`, `idempotencyKey` | `{ ok, id, status: AWAITING_AGENT_PAYMENT }` | `permission-denied`, `SELF_ACTION`, `NOT_CLAIMABLE`, `CLAIMED_BY_OTHER` |
| Release | `staffOps` | `action: releaseClaim`, `withdrawalId` | `{ status: WAITING_FOR_AGENT }` | `permission-denied` unless claiming agent or admin |
| Proof | `staffOps` | `action: submitWithdrawalProof`, `withdrawalId`, `referenceNumber`, `proofImageUrl` | `{ status: PENDING_CONFIRMATION, verifiedPayment: false }` | `SETTLED`, `PROOF_FROZEN`, `NOT_CLAIMED`, `CLAIMED_BY_OTHER`, `SELF_ACTION`, `invalid-argument` |
| Reject | `staffOps` | `action: rejectWithdrawal`, `withdrawalId`, `reason` | `{ status: REJECTED, refunded }` | `SELF_ACTION`, not rejectable, other agent's claim |
| Manual Solana | `staffOps` | `action: createManualWithdrawal`, `targetUserId`, `method: solana`, `amount`, `coin`, UUID `idempotencyKey` | `processWithdrawal` result (`id`, `amount`, `feeAmount`, `netAmount`, `payoutState`) | `SELF_ACTION`, `OWNER_MISMATCH`, `permission-denied`, P2P refused, `WALLET_NOT_VERIFIED`, `WALLET_MISMATCH` |
| Owner cancel/confirm | `updateP2pWithdrawal` | `withdrawalId`, `action: cancel \| confirm`, optional `reason` | `{ ok, id, status, alreadyDone, newBalance? }` | `not-found` (not owner), `OWNER_MISMATCH`, `PROOF_REQUIRED`, `failed-precondition` |

No staff finalize-as-paid action. Do not treat proof as a completed payout.

Mobile still calls the old client cancel/confirm writes. Those rules now deny them. Mobile was not edited. It needs to call `updateP2pWithdrawal` before a rules deploy.

## Still open (next release-blocker batches, not in this patch)

- No `staffOps` action for proof, finalize, or manual payout completion. Web still writes those itself: `FirebaseService.submitWithdrawalProof` and `confirmP2pWithdrawalCompleted`. Claim staff may still record a claim or proof on `withdrawal_requests`; approve, reject, and the balance stay on `staffOps`.
- Host listing screens now query `hostId` from the signed-in token plus `rentalId` or `propertyId`. A stranger's listing-id-only query stays denied. The party who did not press complete does not receive the other completion quest from that click; they call `awardPoints` for themselves with that job id.
- `complete_profile_trust` is not granted from `users.idVerified`. `verify_account` uses the Auth token `email_verified` and `phone_number`. `connect_solana_wallet` requires `wallet_verified`.
- `isAdminOrStaff()` still trusts users-doc flags for non-money desk access (support chats, moderation). It does not authorize treasury reads, `p2p_agents` writes, withdrawal approval, escrow money fields, or booking-request reads.

## Safe web client config

A compile with `ENV=dev` and empty defines is not a production build. Firebase web apiKey, projectId, and appId already live in `DefaultFirebaseConfig` and are public client config.

Public values a real dev/uat/prod bundle needs when those features are used: `APPCHECK_SITE_KEY` (App Check site key), `SOLANA_PUBLIC_KEY` or `TREASURY_PUBLIC_KEY` (treasury address, not a secret), and `SOLANA_RPC_URL` if it does not contain an API key. `BASEMAPS_API_KEY` and `CLOUDFLARE_ACCOUNT_ID` are client map keys.

Do not pass these into the Jaspr client: `XENDIT_SECRET_KEY` (no Dart reader; legacy CI define), `IMGBB_API_KEY` (the upload callable holds it; the client fallback must not be how production gets the key), `GEMINI_AI_API_KEY`, and `CLOUDFLARE_API_TOKEN`.
