# Money-field rules lock: deploy order and client blockers

Branch `fix/rules-lock-money-fields`, two commits. Rules are built with the no-mirror build (`firestore.rules` regenerated from `firestore_rules/*.rules`).

## Commit 1: premium / subscription fields and on-chain markers (safe once Phase 1 clients ship)
- Owners can no longer write `subscriptionPlan|StartedAt|PaymentMethod|PaymentAmount|TxId|Status`, and can only move `isPremium`, `premiumUntil` and `accountType` DOWN (expiry downgrade). New profiles cannot be created premium/hybrid.
- `deposit_sol_*`, `deposit_usdt_*`, `sub_sol_*` and `onchain_*` transactions: create and update are staff / Admin SDK only. `onchain_<sig>` is no longer world-readable.
- Still owner-writable: `pendingSubscription`, `lastSubscriptionRejection`, `updatedAt`, `pending_onchain_<uid>_<sig>`.
- Requires: `creditOnchainPayment` deployed and the Phase 1 mobile/web builds live. Old clients can no longer credit on-chain payments.
- Still client-written (blocker for this commit): web balance-paid subscription (`tranyx_app.dart` ~4340-4365, `processTyxbitSubscriptionPayment`, writes `isPremium/premiumUntil/subscription*`), and mobile `transit_repository.dart:3043 updatePremiumStatus` (if still called). Both need `subscribeWithBalance` (or are broken by this commit).

## Commit 2: `tyxBalance` / `reservedBalance` (DO NOT DEPLOY until every item below is a callable)
Every one of these writes the owner's (or, for refunds/payouts, the counterparty's) `users/{uid}.tyxBalance` from a client. After this commit they all fail with permission-denied.

Mobile (`packages/tranyx_mobile/lib/features/...`)
- jobs/providers/job_repository.dart: createJob escrow debit (:53), acceptApplicant (:411), completeJob payout and fees (:676, :770), cancelJob / adminOverrideCancelJob / reclaimInactiveJob / deleteJob refunds (:952, :1081, :1266, :1421)
- profile/presentation/widgets/withdraw_pane.dart:321 (manual P2P withdrawal debit)
- transit/providers/transit_repository.dart: `updateTyxBalance` (:21) used for listing fee, booking charge (:331, :1458), security deposit, refunds, host payouts, penalties (about 30 call sites, :64-:2884), plus :3343, :3460, :3518 (deduct / restore)

Web (`packages/tranyx_web/lib/...`)
- services/firebase_service.dart: reconcilePendingEscrows (:1257-:1388), updateTyxBalance (:1745), deductTyxBalanceSafely (:1805), cancelJob / reclaimInactiveJob / adminOverrideCancelJob (:2004, :2141, :2285), resolveDispute (:2484-:2581), rental/property listing fee, booking charge, refunds and host payouts (:3325-:6607), approveDepositRequest (:7873), requestP2pWithdrawal (:7994), cancelP2pWithdrawalRequest (:8319, :8392)
- client/tranyx_app.dart: balance-paid subscription (:4353), job post / complete / payout (:5791, :6110, :6490, :7127, :8858)
- client/widgets/withdraw_modal.dart:301

Admin portal (`~/Desktop/tranyx_admin_portal`, read-only grep): staff writes in `pages/withdrawals.dart` (:1185, :1202), `pages/disputes.dart` (:194, :220), `pages/deposits.dart` (:1259, :1305) and `pages/subscriptions.dart` (:377). These keep working because the rules still allow `isAdminOrStaff()`. Verify the signed-in staff accounts really satisfy it (admin claim or verified staff-domain email) before deploying.

Other things the grep turned up but this branch does not change
- `transactions/*` ledger docs are still owner-creatable with a client-chosen `type` (only payout / rebate / fee_deduction and structured ids are restricted). Nothing server-side should trust them as proof of payment.
- `deposit_requests`, `subscriptions` and `users/{uid}/ledger|transactions|points` are owner-writable.
- `wallets/{uid}.balance` is owner-writable but nothing reads it as money.

## Deploy order
1. Deploy Cloud Functions (`creditOnchainPayment`, withdrawal + payout, balance subscription / job / rental money callables) to the project. Needs Blaze.
2. Ship the mobile and web builds that call them.
3. Deploy rules commit 1.
4. Only when no client path above writes `tyxBalance`, deploy rules commit 2.
