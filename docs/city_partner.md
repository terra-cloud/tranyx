# City Partner License (TRAD-15)

Backend contract for the admin panel. The panel calls these Cloud Functions and reads only the collections listed here. It does not write partner, revenue, statement, or payout documents itself.

Self-serve signup, online license-fee payment, and partner-run promotions are out of scope. Partners cannot suspend users.

## Who can call what

Super admin means an ID token with the admin claim `admin: true` and role `admin`, `superadmin`, or `super_admin` (or `superadmin: true`). That is the same top account `syncStaffAccess` provisions as admin. A staff, agent, or partner token is rejected.

A partner token is exactly:

```json
{ "admin": false, "role": "partner", "partnerId": "<auth uid>" }
```

`partnerId` is the Auth uid and the `partners/{partnerId}` document id. `role: partner` is not a staff role and is not accepted by `isClaimStaff` or `isClaimAdmin`.

Both callables are `onCall` in `us-central1` and enforce App Check the same way as `syncStaffAccess`.

### `partnerAdmin`

Super admin only.

| `action` | Body | Result |
| --- | --- | --- |
| `create` | `email`, `areas[]`, optional `licenseStart` (ms), `termMonths` (default 36), `licenseFeePaid` (default 0), `partnerShareBps` (default 7000), `targets` | Creates the Auth user if needed, sets the partner claim, writes `partners/{uid}` |
| `update` | `partnerId`, any of `areas`, `partnerShareBps`, `targets`, `licenseFeePaid`, `licenseStart`, `termMonths` | Recomputes `renewalDate` when the term or start changes. Relocks areas only while the license is active |
| `suspend` | `partnerId` | `status: suspended`, area lock released |
| `deactivate` | `partnerId` | `status: expired`, area lock released |
| `reinstate` | `partnerId` | `status: active` if `renewalDate` is still in the future and the areas are free |
| `approvePayout` | `payoutId` | `pending` → `approved` |
| `markPayoutPaid` | `payoutId` | `approved` → `paid` |
| `setRevenueConfig` | `includeSubscriptions` boolean | `partner_config/revenue.includeSubscriptions`. Default is off |
| `overview` | none | Every partner's KPIs, unpaid payouts, and flags |

`areas[]` items are `{ city, municipality?, province?, region? }`. The exclusive key is the slug of `municipality` or else `city`: lowercased, non-alphanumerics become hyphens. `Calbayog` and `Calbayog` plus a different province are the same area. `Calbayog` and `Calbayog City` are different slugs (`calbayog` and `calbayog-city`); the panel should save the same slug it writes on listings. One to ten areas. A second **active** partner for that slug returns `already-exists` / `DUPLICATE_AREA`. Suspended and expired partners do not hold the lock.

`targets` defaults to `{ activeListings: 30, activeProviders: 30, byMonth: 6 }`.

`tranyxShareBps` is `10000 - partnerShareBps`.

### `partnerDesk`

A partner must present Identity Platform MFA: `firebase.sign_in_second_factor` of `totp` or `phone`. Without it the callable returns `failed-precondition` / `MFA_REQUIRED` and Firestore rules deny the partner token. This repo cannot enroll the factor. Turn on Identity Platform MFA for the workspace project and enroll each partner (TOTP or phone) in the Firebase console before they sign in. A super admin may call `dashboard`, `statement`, `statementCsv`, and `directory` by passing `partnerId` and does not need that factor. `overview` is super-admin only.

| `action` | Body | Result |
| --- | --- | --- |
| `dashboard` | optional `partnerId` for a super admin | KPIs below |
| `statement` | `period` `YYYY-MM` (default: current Asia/Manila month), optional `partnerId` | Statement JSON. PDF is rendered by the client from this payload |
| `statementCsv` | same | The statement plus a `csv` string |
| `directory` | `areaKey`, `kind` `users` \| `rentals` \| `properties` \| `jobs` | Masked rows. Another area returns `permission-denied` / `OUTSIDE_AREA` |
| `review` | `kind` `rental` \| `property` \| `job` \| `provider`, `id`, `decision` `approved` \| `verified` \| `flagged`, `reason` required for `flagged` | Writes `partnerReview` on that document and an audit row. `suspended` is rejected |
| `overview` | none | Same payload as `partnerAdmin` overview |

Suspended or expired partners are locked out (`LICENSE_INACTIVE`).

## Firestore

Clients do not write these. Rules allow a super admin (`isClaimAdmin`) to read them. An **active** partner with MFA can read only their own partner, audit, statement, and payout rows, and `area_revenue` rows whose `areaKey` they cover.

| Collection | Id | Purpose |
| --- | --- | --- |
| `partners/{partnerId}` | Auth uid | Profile: `areas`, `areaKeys`, `licenseStart`, `termMonths`, `renewalDate`, `licenseFeePaid`, `status` (`active` \| `suspended` \| `expired`), `partnerShareBps`, `tranyxShareBps`, `targets` |
| `area_assignments/{areaKey}` | city slug | `{ partnerId, active, city, municipality, province, region, areaKey }`. `active: true` is the exclusive lock |
| `partner_audit_log/{id}` | `pa_<action>_<partnerId>_<ms>` | Every admin and review action |
| `area_revenue/{id}` | `<source>_<sourceId>` or that id plus `__reversal` | One settled or reversing line |
| `area_revenue_index/{id}` | same ids | Idempotency. Not readable by clients |
| `partner_statements/{partnerId}_{YYYY-MM}` | | Last statement snapshot written by `partnerDesk` |
| `partner_payouts/{partnerId}_{YYYY-MM}` | | `amount`, `status` `pending` \| `approved` \| `paid` |
| `partner_config/revenue` | | `{ includeSubscriptions: boolean }` |

`area_revenue` fields: `source` (`vehicle_rental`, `property_rental`, `gig_job`, `service_job`, `subscription`), `sourceId`, `areaKey`, `status` (`settled` \| `reversed`), `gross`, `platformRevenue`, `partnerShare`, `tranyxShare`, `partnerId`, `period`, `occurredAt`. A reversal stores the negated amounts in the month it is detected. Subscriptions are skipped unless `includeSubscriptions` is true.

### Area on existing records

Listings, jobs, bookings, and tickets the partner desk should show need `areaKey` set to the same city slug. The revenue job uses `areaKey`, then `city` / `registeredCity` / `municipality` on the record, then the same fields on the host, renter, or creator. A partner token cannot list a collection unless the query is `where('areaKey', '==', <their slug>)`. Guests and normal users are unchanged. Staff and admin claims are unchanged.

Partner tokens cannot read raw `users` (email, phone, wallet), `settings/platform_fees`, `platform_config`, `config`, `system_config`, KYC, escrow money, exact `private/location`, or another area's listings, jobs, bookings, or tickets. `directory` kind `users` returns `uid`, a shortened `displayName`, `areaKey`, `city`, `accountType`, and `partnerReview` only.

`attributePartnerRevenue` runs every 60 minutes. It scans up to 100 `rental_escrows`, `property_escrows`, and `platform_fees` documents per run (document-id cursor, then wraps). Released escrows and completed jobs (`categoryGroup == services` is a service job, otherwise a gig) become settled lines. `Refunded` / `Cancelled` escrows and cancelled jobs write a reversal. The previous Asia/Manila month gets a `pending` payout if it has lines and the payout is not already approved or paid. A license whose `renewalDate` has passed is deactivated on that run.

## KPIs

`dashboard` and each `overview` row:

- `activeListings` — rentals and properties in the partner's areas whose status is available, booked, rented, active, or open, and not `isDeleted`
- `activeProviders` — distinct `hostId` on those listings, plus `creatorId` or `acceptedApplicantId` on open jobs
- `bookings` — `rental_requests` and `property_requests` in the area that are not cancelled, rejected, or refunded
- `completedJobs` — jobs in the area with status completed or successful
- `grossVolume`, `earningsToDate`, `earningsThisMonth` — sums of `area_revenue.gross` and `partnerShare` for this partner
- `newUsers` — users with that `areaKey` and `createdAt` in the current Asia/Manila month
- `behindTarget` — `monthsElapsed` (30-day months from `licenseStart`) is at least `targets.byMonth` and listings or providers are still under the target
- `licenseExpiring` — `renewalDate` is within 30 days
- `unpaidPayouts` — payouts still `pending` or `approved` (overview only)

## 2FA

Firebase Auth MFA is an Identity Platform feature. The deployed functions only see it after the project has Identity Platform and the user has enrolled TOTP or phone. Until that enrollment exists, partner rules and `partnerDesk` fail closed. Super-admin partner management does not require the partner factor.

## CSV

`statementCsv` returns the statement fields plus:

```text
period,source,sourceId,areaKey,status,gross,platformRevenue,partnerShare,tranyxShare
```
