# Web redesign parity audit — origin/develop (6335883) vs feat/web-redesign-batch-a

Method: (1) file diff (21 Dart/asset files changed; all other views/widgets/services/components are byte-identical to develop),
(2) every `s.*`/`state.*` call from views/widgets counted in develop vs HEAD (327 vs 342 distinct refs; only 8 dropped, listed below),
(3) every `show*` modal flag, `JobsView/ProfileView/TransitMode/RentalCategory/AuthView/AppTab` enum value reference-count compared,
(4) UI string/copy diff on auth/home/sidebar/header/legal pages.
"Reachable" = a user-facing control in HEAD still opens/triggers it. Unchanged files keep their entry points unless a changed file hosted the entry point.

| # | Feature (develop) | Reachable in redesign? | Where | Fix |
|---|---|---|---|---|
| 1 | Email/password sign-in, show/hide pw, error mapping | yes | W01 Sign In | — |
| 2 | Google sign-in / Google register complete | yes | W01 + register path | — |
| 3 | Phantom sign-in + "wallet will be linked after registration" banner | yes | W01, W02/W03 banner (auth_view:556) | — |
| 4 | Register path (Employer / Nyxian), details form, password rules, Terms/Privacy links | yes | W02/W03 | — |
| 5 | Registration auto-login + welcome walkthrough modal | **partial → fixed** | W04 now requires return to login | `pendingWalkthrough` flag opens walkthrough on first login after email sign-up |
| 6 | Pending QR completion verify after register/login | yes | handleLogin still runs executePendingQrVerification | — |
| 7 | Forgot password (email reset) | yes | W-Forgot (new AuthView.forgotPassword) | — |
| 8 | Email verification mail / resend | yes (new) | W04 | — |
| 9 | Mobile app prompt modal, wallet selection modal, session-expired modal, wallet reconnect prompt | yes | rendered by tranyx_app build (unchanged) | — |
| 10 | Splash (showWebSplash) | yes | tranyx_app | W00 frame still to restyle |
| 11 | Terms of Use / Privacy Policy / About routes | yes | /terms-of-use /privacy-policy /about, all copy preserved | — |
| 12 | Dark/light toggle | yes, now system-first | top_header toggle → setThemePreference | — |
| 13 | Guest (logged-out) browse | new (W05) | guest gating: Messages/Profile → sign-up | — |
| 14 | Sidebar nav Dashboard/Jobs/Rentals/Messages/Profile + logout | yes | sidebar.dart | — |
| 15 | Sidebar/bottom-nav unread chat dots + counts | **partial → fixed** | icon-rail (md–lg) hid the count pill and the dot | dot kept on rail, pill at lg+ |
| 16 | Bottom nav (mobile) unread dots | yes | bottom_nav.dart unchanged | — |
| 17 | Top header: page title, notifications dropdown, avatar/profile, account-type badge | yes | top_header.dart (title kept; global search added per W10) | — |
| 18 | Home: hybrid mode toggle (Nyxian/Employer) + holdbacks reload | yes | home_view | — |
| 19 | Home: News & Promos tab, promo-code redeem, news actions | yes | home_view (tab label restored to "News & Promos") | label fix |
| 20 | Home: Active P2P deposit/withdraw banner (+cancel/confirm) | yes | home_view | — |
| 21 | Home: active trackers & trips, ongoing gig + chat with unread count | yes | home_view | — |
| 22 | Home: global gig search | yes | home_view + top_header | — |
| 23 | Home: Top Services "Browse" → full category taxonomy modal | **no → fixed** | Top Services now six hard-coded chips; modal opener had been replaced | "See All" opens CategoryModal again (modal → handleHomeSearch) |
| 24 | Home: Near-me vehicles/properties (Nyxian + Employer), transit & real-estate teasers | yes | home_view | — |
| 25 | Home: wallet quick stats, Deposit/Withdraw/wallet action menu | yes | W10 wallet card, sidebar Tyxbit mini | — |
| 26 | Jobs browse: search, category chips, geofence, Remote toggle, sort, Recommended/High Paying | yes | jobs_view (+Reset via resetJobFilters) | — |
| 27 | Jobs panes Active / Applied / History, My Postings (Employer) | yes | jobs_view ("Applied" label → "My Applications" per Figma) | — |
| 28 | Job details, apply, review, success; post_job create flow, map pickers, AI draft | yes | jobs_view / pages/post_job unchanged | — |
| 29 | Edit job, delete confirm, job order details, report/dispute/authenticity | yes | unchanged | — |
| 30 | Contract signing modal + PDF viewer | yes | unchanged (showSignContractModal/showPdfViewerModal counts equal) | — |
| 31 | Completion QR scanner, employer fee popup, rating popup | yes | unchanged | — |
| 32 | Navigation map / live tracker | yes | components/navigation_map.dart unchanged | — |
| 33 | Rentals: Rent / Host / History modes, Vehicles / Properties | yes | transit_view (TransitMode & RentalCategory refs equal/up) | — |
| 34 | Vehicle filters: search, distance, max price | yes + type & rent-option (new) | transit_view | — |
| 35 | Vehicle "Map" view toggle | yes (new) | transit_view `_rentalsMapView` is a live MapLibre map with live vehicle markers (b3d6e8d) | — |
| 36 | List/book/extend/manage/edit vehicle; vehicle Q&A; rental tracker map; rental details | yes | modals unchanged | — |
| 37 | List/book/manage/edit property; property Q&A | yes | unchanged | — |
| 38 | P2P admin panel (Cash P2P agents) | yes | widgets/p2p_admin_panel.dart unchanged | — |
| 39 | Messages: conversations, search, All/Jobs/Rentals/Properties/Support filters, chat widget (ImgBB photo), support chat | yes | messages_view (chip labels shortened per Figma) | — |
| 40 | Chat fullscreen photo, employer profile modal | yes | unchanged | — |
| 41 | Profile menu: Personal, Professional, Account Settings, Payment Methods, Trust & Verification, Help & Support, History, Reviews, Rewards | yes | profile_view menu (no Subscription menu entry; subscription flow lives in the profile main pane, see row 44) | — |
| 42 | Profile Withdraw Funds | yes (added) | profile menu + `_WithdrawPane` + modal | W54 full screen pending |
| 43 | KYC ID / Background modals, verification levels | yes | showKycIdModal/showKycBgModal counts equal | — |
| 44 | Subscriptions incl. Cash P2P, Hybrid upgrade | yes | subscription flow is on web inside the profile main pane (`_ProfileMain`, profile_view.dart ~454-458, 727, 1167), unchanged from develop | — |
| 45 | Rewards / quests | yes | profile_view rewards pane | — |
| 46 | Wallets: Solana/Phantom link, deposit (P2P + on-chain), refunds, withdraw (P2P agent rail + Solana) | yes | wallet_action_modal / payment_modal / withdraw_modal unchanged | — |
| 47 | Notifications + toasts | yes | showAppToast / notifications dropdown | — |
| 48 | Onboarding walkthrough replay | yes | profile_view:4189 | — |
| 49 | Role switching (hybrid toggle) | yes | home hybrid toggle | W14/W15/W16 frames pending |
| 50 | Delete-confirm, SMS modal, category modal (post-job category pick) | yes | counts equal | — |

Dropped refs found by the call-graph diff: pendingWalletPublicKey (8→1, banner moved into one helper — verified), handleGoogleRegisterComplete (2→1, role-picked helper — verified),
hasUnreadJobChats/hasUnreadRentalChats (sidebar — fixed #15), showCategoryModal (home — fixed #23), activeJobFilter/includeRemoteJobs (refactored into openJobsBrowse/resetJobFilters — verified).

Firestore rules not touched; no new deps.


## Addendum — merged with Kelvin's develop inventory (canvas f4f6b07a, 2026-10-29)

| Kelvin item | Roles | Status in this branch | Frame | Notes |
|---|---|---|---|---|
| Login email/Google/forgot | guest | yes | W01 | Mobile auth set is Ron's; not redone here |
| Register role path, details, Google register | guest | yes | W02–W03 | Google-pending path: auth_view:411 → handleGoogleRegisterComplete, walkthrough still opens |
| Phone OTP (reCAPTCHA) | all | yes (SMS modal) | none named | showSmsModal opener sites unchanged (tranyx_app:7211/7220 = develop 6983/6992); modal untouched |
| KYC pending, ID/BG modals, Trust pane | all | yes | W51–62 range | Modals + trust pane unchanged from develop; restyle pending Ron |
| Guest browse | guest | yes | W05 | live data |
| Dashboard Nyxian / Employer / Hybrid | all | yes | W10 / W11 | W11 built this pass |
| Shell: sidebar, bottom nav, header, notifications, dark toggle, session-expired | all | yes | W12/W13, W70 | rail unread dot fixed; W14/W15 mobile bar + mode switch in progress |
| Jobs browse, category modal, filters, map | nyxian | yes | W20 | modal opener restored on Home |
| Job details apply/counter/Q&A/report | all | yes | W22 | report/ratings write denied by rules on dev (Kelvin H8) – rules out of scope here |
| Post job incl. AI description assist, promo | employer | yes (unchanged) | W29 AI draft modal 56:3556 / 56:4664 | Gemini assist = existing showAIDraftModal; restyle to W29 tokens later |
| Apply (AI cover note) | nyxian | yes (unchanged) | W23 56:2668 / 56:4008 | existing apply view kept |
| Apply / review applicants / hire / success | both | yes | W23–W29 | W25 review applicants 390 pending |
| Lifecycle: SLA ack, QR, complete, abandon, dispute | both | yes | W23–29, W41 | unchanged |
| Edit/delete/rating modals | both | yes | | unchanged |
| Rentals vehicles/properties browse + book, host create/edit/manage, contracts+PDF, extend, tracker map, Q&A, promo, history | renter/host | yes | W30–39 | Home near-me tiles now open the booking modals again (were routing to tab) |
| Messages list/archived + chat states + photo | all | yes | W40/W41 | |
| Profile main + panes | all | yes | W50–W62 | |
| Withdraw | all | yes | W54 | full page built (2edb992); modal kept for wallet quick-actions |
| Subscription / PRO | all | yes | on web in profile main pane (row 44) | web ProfileView.subscription renders _ProfileMain (same as develop) — not a regression; W15 "See Hybrid PRO" CTA lands on it |
| P2P agent desk/admin panel | agent/admin | yes (p2p_admin_panel.dart untouched) | **W60** 65:7567 / Dark 65:14589 | restyle pending; reachable as in develop |
| Interactive walkthrough | new users | yes | **no frame – Ron designing** | opens after first login post sign-up, replay from Profile |
| Public marketing /, /about, /post-job, /privacy-policy, /terms-of-use | guest | yes (routes unchanged lib/app.dart) | W06 for legal (6:200 / Dark 67:11656); landing/about marketing **no frame – Ron designing** | |
| Promo-code entry | all | yes | W10 + states W12 (53:4603 / 53:4811) | Home news tab + W11 compact card; booking/post-job promo fields untouched |
| Responsive rules | all | partial | W90 | |

Newly found while building W10/W11 (fixed): Nearby Rentals tiles used wrong vehicle keys (title 'Vehicle', 'Rate on request') and gradient instead of the live photo.
Open: Rentals "Map" toggle (W30) is a text notice, not a live map.

Status 2026-10-29: W58 Transaction History keeps every ledger filter, itemized fee card, pagination, rejected/cancelled rows and the P2P Desk & Admin toggle; adds mode tabs (Earnings/Purchases/Deposits/All), period select, live stat cards, Export CSV. W00 splash restyled (static index.html + Dart splash). W21 applicants panel keeps Edit/Accept/Reject/Chat/Bond flows via the same _ReviewApplicants component.

Status 2026-10-29 (round 2):
- W60 P2P desk restyled (agent-only badge, segmented tabs, dashed empty state, light-theme mapping via `.p2p-desk`); all queue/inspector/settings flows unchanged.
- W29 AI draft modal restyled + Regenerate; W23 Apply restyled (live job summary, Nyx AI cover note, counter-offer toggle card, Cancel). Gemini generate calls unchanged.
- W12 states: news empty/error (Try Again)/skeleton, Current Gig + Ongoing Job helper copy. No new filters, so no "Reset Filters" button on news cards.
- W30 Rentals Map: vehicles only (no properties toggle in develop either); live markers from `pickupLat/pickupLng`, listings without a real pickup location are not pinned.
- Walkthrough flag now persisted (localStorage `tranyx_walkthrough_for`, per email).
- W15 Switching skeleton (≤450 ms min) built.
- W25 frames (per Ron): 390 Light 58:3092 / Dark 58:4746; 1440 Light 58:2934 / Dark 58:4588. Node 16:2115 was an orphan. Built: status chips All/Pending/Hired/Not selected (+Bonded/Top rated), Accept & hire, Chat, empty state. "Not selected"/"Reconsider" buttons need a reject/reconsider backend action that does not exist in develop — not built (no client-side invented semantics).
- Row 44 / subscription: not on web in develop either.
Verified by headless Chrome screenshots (guest-reachable): splash, sign-in, guest home, Jobs browse, Rentals at 390/834/1440 light; 390/1440 dark. Everything behind login is design-reviewed only.

Status 2026-10-29 (round 3, missing-screens pass):
- W36 listing wizard (list/edit vehicle + property) restyled in place — same fields, steps and write paths (8813fba). Shared `.rw-wizard`/`.rw-overlay` skin also applied to book/manage/details/extend/Q&A/KYC/sign-contract/payment/wallet-action/rating/delete/session-expired modals (5901cda).
- W31–W33 rentals page: one toolbar (Rent|Host|History · Vehicles|Properties), no emoji, "Host dashboard"/"Rental history" headings, property filters restyled (all 6 filters kept), 3/2/1 grid, empty state with Reset Filters, List-property CTA. Host mode still switches Vehicles/Properties (all features kept).
- W51–W57 profile panes: 32px headings + helper lines; back arrow only below md; pf-pane control skin. W24 create job skin; W26 success card.
- Still partial: W13 dropdown, W25 reject (backend), W27/W28 layouts, W32 stacked host sections, W33 breakdown cards, W41 chat states, W59 tab merge. Design-blocked: KAN-140/141, photo viewer, legal/consent, 834/1194.
- No entry points removed: all show* flags and TransitMode/RentalCategory/ProfileView values unchanged.

Status 2026-10-29 (round 4, W20→W70 sequence pass; all pushed on feat/web-redesign-batch-a):
- W20 d1f4354 jobs filter bar; W21 f42cec9 "My Postings"; W22 da8385a job details order + payment breakdown; W23 b976eb9 apply badge/row; W24 ecbb468 create job as one page (sections, gates kept, "Post job & lock escrow"); W25 5cb06ef review badge (reject/reconsider still backend-blocked); W26/W36 earlier.
- W27 02613d4 vertical tracker stepper (real statuses); W28 d0da3ad live-navigation chrome + order sheet (ETA/Distance units assumed s/m); W29 eae3063 modal skins.
- W30 9c39487 / W32 3db89b5 / W33 bd4a02e rentals labels, host stack, history cards; W34/W35 09954f4 book vehicle/property as pages; W37/W38 3313c97 manage + rental details pages; W39 73e4da7 tracker & extend page.
- W40 acc70e8 messages split pane (>=1024px; resize only re-evaluated on next app setState); W41 chat states already present.
- fb3f636 PDF viewer hardened: viewer accepts only data:application/pdf;base64,JVBERi… or https firebasestorage.googleapis.com/storage.googleapis.com URLs under this project's bucket (Uri.parse); no iframe (Chrome refuses PDFs in sandboxed iframes) → PDF.js + "Open in new tab" Blob + Download; lease upload cap 700 KB with visible errors (list/edit vehicle & property).
- W50 5e85103 wallet CTAs per account type; W51+ b4dbd59 profile sub pages single column + breadcrumb; W54–W58 covered (W58 stat cards, CSV).
- W59 d1df39a Reviews & rewards (tabs, both columns lg+; both menu entries still route, to their tab). W60 already built (P2P desk). W61 50f6812 top-up as shell page ("Wallet · Top-up"). W62 8d7427e withdraw modal skin; request states (Paid/Rejected/In review) live on W54 page.
- W13 + W70 db7bed0: notifications dropdown empty-state copy and mobile full-width sheet; guest gate modal "Create an account to continue" (Create account / Sign in / Continue browsing) for locked guest actions. Session-expired modal pre-existed.
- Not built: W25 Not selected/Reconsider, "Save draft", W26 "Your ask" (backend); W13 "Reset Filters"; W70 Reconnect wallet / Get the Tranyx app / Permission-denied banner (no semantics/URLs); KAN-140/141, photo viewer, legal/consent, most 834/1194 frames (design-blocked).
- Verification: dart analyze 0 errors; dart test 69 pass / 4 fail (emulator-dependent integration tests, same as baseline). Guest shell loads (headless Chrome); gate modal verified by CDP click on Messages. Logged-in screens not click-tested.

Status 2026-10-29 (W70 banners):
- Reconnect wallet: existing `WalletReconnectModalComponent` restyled to the W70 frame ("Reconnect your wallet", Reconnect wallet / Not now); still opened only from `autoConnectPhantomIfLinked` (linked wallet not connected). Handlers unchanged.
- Get the app: card shown only below md, dismissible (localStorage `tranyx_get_app_dismissed`), store buttons from `--dart-define=APP_STORE_URL=… / PLAY_STORE_URL=…` (https only); with neither set it never shows. The existing UA-based "Open Tranyx Mobile" prompt (Solana dApp Store) is untouched; the new card is suppressed while it is showing.
- Permission denied: raised from the central request wrapper in firebase_service.dart after retries when a Firestore/Functions call fails with 403 / permission-denied. Banner shows static copy plus a random `PD-XXXX-XX` ref (6 chars, secure RNG), Copy ref, Contact support (→ Help & Support, signed-in only), dismiss. No Firebase message, path or document id in the UI; console log is `[permission-denied] ref=… code=…` only. Duplicate reports within 2 s are collapsed.
- Verified on localhost (guest, 390): app loads, banners hidden when env is unset. Banner/modal visuals not click-tested (need a linked wallet / store env / a 403). New test: test/permission_ref_test.dart.

Status 2026-10-29 (pdf.js hardening, Kelvin FAIL on fb3f636): pdf.js stays on 3.11.174 with `isEvalSupported:false` on both getDocument calls (CVE-2024-4367), sha384 SRI + crossorigin on pdf.min.js and pdf.worker.min.js (worker loaded as an SRI script → main-thread worker, no unpinned worker URL), download link `rel="noopener noreferrer"`, document cache keyed on SHA-256 of the full source. Follow-up: upgrade to 4.x together with re-pinning for the KAN-142 CSP (module/worker paths change).
