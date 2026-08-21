# Tranyx QA Acceptance Criteria (AC) & Test Matrix

This document provides a single source of truth for QA agents and automated testing suites to compare implemented behaviors against platform specifications.

---

## 1. Job Cancellation Integrity & Active Hire Protection Matrix

### User Stories
- **Worker / Nyxian Story**:
  > *As an Accepted Nyxian (Worker/Freelancer),*
  > *I want the system to prevent the Employer from unilaterally cancelling the job once my application is accepted/hired,*
  > *So that my committed time, resources, travel, and preparation are safeguarded against arbitrary abandonment.*
- **Employer Story**:
  > *As an Employer,*
  > *I want clear status indicators explaining that cancellation is locked due to an active hire,*
  > *So that I understand why the normal cancel button is disabled and know how to proceed (Admin/Support Dispute).*

### Acceptance Criteria Matrix

| AC ID | Test Case ID | Scenario / Condition | Given | When | Then (Expected Outcome) | Test File |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-CNCL-01** | `TC-CNCL-01` | Cancellation of Open Job & Audit Trail | Job is in `OPEN` / `PUBLISHED` state with no accepted hire | Employer initiates cancellation | Job status changes to `CANCELLED`, 100% of escrow is refunded, and an immutable log is written to `/job_cancellation_logs/{logId}` with action `UNILATERAL_CANCEL`. | `packages/tranyx_mobile/test/job_repository_test.dart` |
| **AC-CNCL-02** | `TC-CNCL-02` | Automatic Rejection of Pending Applications | Job has 2+ pending applications and no hired worker | Employer cancels the open job | All pending application documents in subcollection `jobs/{jobId}/applications` transition to status `REJECTED_JOB_CANCELLED`. | `packages/tranyx_mobile/test/job_repository_test.dart` |
| **AC-CNCL-03** | `TC-CNCL-03` | Unilateral Cancel Disabled on Active Hire | Job status is `NYXIAN_ACCEPTED` / `IN_PROGRESS` (`job.isHired == true`) | Employer views Job Details in Mobile or Web | Unilateral cancel button is hidden/disabled; a protected banner (`_buildProtectedHireBanner` / `Cancellation Locked`) is displayed with Support / Admin Dispute guidance. | `packages/tranyx_mobile/test/job_repository_test.dart` & `packages/tranyx_web/lib/client/views/jobs_view.dart` |
| **AC-CNCL-04** | `TC-CNCL-04` | Backend Protection Lock on Hired Jobs | Job has an assigned freelancer (`acceptedApplicantId != null`) | Client/API invokes `cancelJob(jobId, employerUid)` | System throws `JOB_ALREADY_COMMITTED` exception; no status change or escrow refund occurs. | `packages/tranyx_mobile/test/job_repository_test.dart` |
| **AC-CNCL-05** | `TC-CNCL-05` | Terminal State Cancellation Guard | Job is in terminal status (`COMPLETED`, `CANCELLED`, `ADMIN_CANCELLED`) | User attempts to cancel the job | System throws `INVALID_STATE_TRANSITION` / `JOB_IS_TERMINAL` exception. | `packages/tranyx_mobile/test/job_repository_test.dart` |
| **AC-CNCL-06** | `TC-CNCL-06` | Admin Override Cancellation & Validation | Job is locked or disputed with active hire | Admin triggers `adminOverrideCancelJob(jobId, adminUid, reason)` | Validates `reason.length >= 20` (throws exception if < 20 chars); sets status to `ADMIN_CANCELLED`, refunds escrow, dispatches notifications, and writes audit record to `/job_cancellation_logs`. | `packages/tranyx_mobile/test/job_repository_test.dart` |
| **AC-CNCL-07** | `TC-CNCL-07` | Application Block on Terminal Jobs | Job is `CANCELLED` or `COMPLETED` | Freelancer attempts to call `applyToJob(...)` | System throws exception preventing application on inactive/terminal jobs. | `packages/tranyx_mobile/test/job_repository_test.dart` |

---

## 2. AI Auto-Draft Generator & Profanity Immunity Matrix [LOCKED - VERIFIED & COMPLETED - DO NOT MODIFY]
* **Status**: **LOCKED & ENFORCED** (All Acceptance Criteria AC-DRAFT-01 through AC-DRAFT-07 are completed, verified, and locked against modification).

### User Story
> *As an Employer creating a job posting,*
> *I want the Auto-Draft generator to tailor the job description based on my selected Job Category without falsely blocking clean text,*
> *And I want an explicit "Accept" or "Discard/Edit" option before the draft replaces or populates my description field,*
> *So that I stay in full control of my job posting content and never get blocked by false moderation flags.*

### Acceptance Criteria Matrix

| AC ID | Scenario | Given | When | Then (Expected Outcome) | Test File |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-DRAFT-01** | Scenario 1: Category-Specific Prompt Tuning | Employer selects Category = `"Vehicle Rental"` or `"Courier / Delivery"` and enters prompt (e.g. `"Need pickup in Bacoor"`) | Auto-Draft generator is triggered | Generated description contains tailored logistics/vehicle details (vehicle type, pickup/drop-off locations, timing, cargo handling). | `packages/shared/test/ai_service_test.dart` & `packages/tranyx_mobile/test/nyx_ai_assistant_service_test.dart` |
| **AC-DRAFT-02** | Scenario 2: No False Positive Profanity Flags | Input prompt contains substrings of banned words (e.g., `"Need assistance"`, `"Fast pass delivery"`, `"Kanto"`, `"Paspas"`, `"Kikiam"`, `"peacock"`) | Profanity check `checkProfanity(text)` runs | Returns `false` (clean text is NOT blocked). System only flags true offensive whole words and phrases. | `packages/shared/test/profanity_test.dart` & `packages/tranyx_mobile/test/nyx_ai_assistant_service_test.dart` |
| **AC-DRAFT-03** | Scenario 3: Discard Action (Zero Overwrite) | AI Draft Preview bottom sheet/modal is displayed | User clicks **"Discard"** | Modal/bottom sheet closes immediately; the description input field remains in its original state with zero overwrite. | `packages/tranyx_mobile/test/ai_draft_bottom_sheet_test.dart` |
| **AC-DRAFT-04** | Scenario 4: Accept Action (Draft Applied & Editable) | AI Draft Preview bottom sheet/modal is displayed with generated/edited text | User clicks **"Use This Draft"** | Modal closes, the target description controller and state are populated with the draft text, and remain fully editable. | `packages/tranyx_mobile/test/ai_draft_bottom_sheet_test.dart` |
| **AC-DRAFT-05** | Scenario 5: Category Mismatch Error Guard | Job title does not align with the selected category (e.g. title is `"Fix leaking kitchen sink"` but category is `"Vehicle Rental"`, or title is `"Motorcycle courier driver"` but category is `"Plumbing"`) | User clicks **"Auto-Draft"** / `generateJobDescription` | System throws `CategoryMismatchException` and displays a clear mismatch warning snackbar/toast (`"Category Mismatch: The job title ... does not match the selected category ..."`), preventing misaligned generation. | `packages/shared/test/ai_service_test.dart` & `packages/tranyx_mobile/test/nyx_ai_assistant_service_test.dart` |
| **AC-DRAFT-06** | Scenario 6: Multilingual Auto-Drafting (Tagalog & Waray-Waray) | Job title is aligned with the selected category and written in Tagalog (e.g. `"Kailangan ng tubero para sa tumutulong lababo"`) or Waray-Waray (e.g. `"Nagkikinahanglan hin panday para hit balay"`) | User clicks **"Auto-Draft"** / `generateJobDescription` | System detects language from prompt keywords and automatically drafts the entire job description in fluent **Tagalog** or **Waray-Waray** respectively. | `packages/shared/test/ai_service_test.dart` & `packages/tranyx_mobile/test/nyx_ai_assistant_service_test.dart` |
| **AC-DRAFT-07** | Scenario 7: Rich Category Duties Invariant (No Raw Title Quoting) | Any job title is entered | User clicks **"Auto-Draft"** / `generateJobDescription` | The generated description synthesizes an actual rich description outlining specific tasks, tools, materials, and safety expectations for that category. It must **NEVER** simply echo or wrap the user's raw prompt in quotes (e.g. `para hit "..."`). | `packages/shared/test/ai_service_test.dart` & `packages/tranyx_mobile/test/nyx_ai_assistant_service_test.dart` |

---

## 3. Dispute Ticket & Admin Portal Integration Matrix

### Acceptance Criteria Matrix

| AC ID | Feature | Given | When | Then (Expected Outcome) | Verification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-DISP-01** | Dispute Ticket Creation | Active hire job is locked from unilateral cancellation | User taps **"Request Dispute Review"** (Mobile) or **"Contact Admin / Support Dispute"** (Web) | Structured document is created in `/disputes/{disputeId}` with `status: 'OPEN'`, `jobId`, `employerId`, `acceptedNyxianId`, `escrowAmount`, `openedByUid`. | `packages/tranyx_mobile/lib/features/jobs/presentation/widgets/job_details_view.dart` & `packages/tranyx_web/lib/client/views/jobs_view.dart` |
| **AC-DISP-02** | Security Rules for Disputes | Authenticated users & Admin Portal Staff | Reading or creating `/disputes/{disputeId}` | Rule `match /disputes/{disputeId} { allow read, write: if isActiveUser() || isAdminOrStaff(); }` permits authenticated dispute generation and admin review. | `firestore.rules` |
| **AC-DISP-03** | Dispute Resolution via Admin Override | Open dispute ticket exists for a gig | Admin triggers override in `tranyx_admin_portal` | Job status is updated to `ADMIN_CANCELLED`, audit log is created, and dispute can be marked `RESOLVED`. | `packages/tranyx_mobile/lib/features/jobs/providers/job_repository.dart` & `packages/tranyx_web/lib/services/firebase_service.dart` |

---

## 4. Vehicle Rental Driver License Requirement (With Driver vs Self-Drive) Matrix

### User Story
> *As a vehicle renter choosing a "With Driver / Chauffeur-Driven" rental,*
> *I want the booking form to omit the Driver's License Number requirement,*
> *So that I am not blocked by an irrelevant form field when I am not the designated driver.*
>
> *As a vehicle renter choosing "Self-Drive",*
> *I want to provide my verified Driver's License details,*
> *So that the vehicle owner and insurance policies are legally protected.*

### Architecture & Payload

```
                    [ Select Rental Type ]
                              │
             ┌────────────────┴────────────────┐
             ▼                                 ▼
    [ Self-Drive Mode ]               [ With Driver Mode ]
             │                                 │
     License Field:                    License Field:
     • Visible                         • Hidden / Removed
     • Required (`validator != null`)  • Skipped (`validator = null`)
             │                                 │
             ▼                                 ▼
   Payload: {                         Payload: {
     driving_mode: "SELF_DRIVE",        driving_mode: "WITH_DRIVER",
     license_no: "N01-XX-XXXXXX"        license_no: null
   }                                  }
```

### Acceptance Criteria Matrix

| AC ID | Test ID | Scenario | Given | When | Then (Expected Outcome) | Verification Test |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-RENT-01** | `TC-RENT-01` | Booking with Chauffeur | User selects `"With Driver"` rental option | User navigates to booking checkout / summary | Driver's License Number field is completely hidden; validation passes without entering license; receipt confirms `"Rental Type: With Driver (Chauffeur-Driven)"`; `licenseNumber` payload is `null`. | `packages/tranyx_mobile/test/transit_repository_test.dart` |
| **AC-RENT-02** | `TC-RENT-02` | Self-Drive with Valid License | User selects `"Self-Drive"` rental option | User inputs valid license (e.g. `"N01-88-123456"`) and submits | Validation passes; booking request created with `licenseNumber: "N01-88-123456"` and `hireWithDriver: false`. | `packages/tranyx_mobile/test/transit_repository_test.dart` |
| **AC-RENT-03** | `TC-RENT-03` | Self-Drive Missing License | User selects `"Self-Drive"` rental option | User submits with empty license field | Submission is blocked; inline/snackbar error is displayed: `"Driver's license number is required for self-drive bookings."`. | `packages/tranyx_mobile/test/transit_repository_test.dart` |
| **AC-RENT-04** | `TC-RENT-04` | Mode Switch Edge Case | User inputs license in Self-Drive, then toggles to With Driver | Mode switch occurs | Field disappears; controller clears or payload ignores input (`licenseNumber: null`); booking succeeds without validation errors. | `packages/tranyx_mobile/test/transit_repository_test.dart` |


---

## 5. Rental Listing Card Gesture Routing & Book Now CTA [VERIFIED & ENFORCED]

### User Story
> **As a** user browsing the rental marketplace,
> **I want** to tap anywhere on a rental listing card to view its full details,
> **While still having** a dedicated "Book Now" button for fast-track booking,
> **So that** discovering listing specs and initiating bookings feel natural and frictionless on both mobile and desktop.

### Architecture & Gesture Routing
```
+-------------------------------------------------------------------+
|  [ Entire Card Wrapped in InkWell / GestureDetector ]              |
|  --> onTap: Navigate to `RentalDetailsScreen(listingId)`           |
|                                                                   |
|   +------------------------------------+                          |
|   | [ Image Carousel / Thumbnail ]     |                          |
|   +------------------------------------+                          |
|   | 🚗 2024 Toyota HiAce Grandia       |                          |
|   | 📍 Naic, Cavite • Diesel • Auto    |                          |
|   | ₱3,500 / day                       |                          |
|   |                                                               |
|   |                  +-----------------------------------------+  |
|   |                  | [ Book Now ] Button                     |  |
|   |                  | --> Stops bubbling / triggers Booking   |  |
|   |                  | --> Navigate to `BookingFlowScreen`     |  |
|   |                  +-----------------------------------------+  |
|   +---------------------------------------------------------------+
+-------------------------------------------------------------------+
```

### Acceptance Criteria Matrix

| AC ID | Scenario | Given | When | Then (Expected Outcome) | Verification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-CARD-01** | Card Body Tap $\rightarrow$ Details View | User is viewing the rental marketplace feed | User taps/clicks anywhere on the card body (image, title, badges, pricing, empty card space) | App navigates / displays the Rental Details Screen / Modal corresponding to that exact listing. | `packages/tranyx_mobile` & `packages/tranyx_web` |
| **AC-CARD-02** | Direct CTA Tap $\rightarrow$ Instant Booking Flow | User is viewing a rental card | User taps directly on the "Book Now" / "Rent Now" button | Action immediately opens the Booking / Date Selection Flow without pushing a redundant details page underneath. | `packages/tranyx_mobile` & `packages/tranyx_web` |
| **AC-CARD-03** | Gesture Isolation & Event Bubbling | User taps the "Book Now" or "Q&A" button | Button click event fires | Event is consumed solely by the button (`e.stopPropagation()` / child gesture interception), preventing duplicate or bubbling navigation triggers. | `packages/tranyx_mobile` & `packages/tranyx_web` |
| **AC-CARD-04** | Hover & Touch Feedback | User hovers (Desktop/Web) or taps (Mobile) on the card | Mouse enters boundaries or screen is touched | Cursor switches to `SystemMouseCursors.click` / `cursor-pointer`, accompanied by hover lift / border highlight on Web and standard `InkWell` splash/ripple on Mobile. | `packages/tranyx_mobile` & `packages/tranyx_web` |
| **AC-CARD-05** | Multi-Category Consistency | User browses different asset categories (Vehicles, Heavy Equipment, Properties) | Listing cards are rendered | Full-card tap and isolated "Book Now" / "Rent Now" button interactions behave identically across all asset categories. | `packages/tranyx_mobile` & `packages/tranyx_web` |

---

## 6. Persistent Calendar Availability with Smart Tier Duration & Rate Optimization (`AC-CAL-01` to `AC-CAL-08`)

### User Story
**As a** vehicle or property renter,  
**I want** an interactive calendar displaying real-time reserved/unavailable dates in red, where selecting a Start Date and a flexible duration ($N$ days, weeks, or months) visually highlights the computed span on the calendar, validates for date conflicts, formats all schedule timestamps uniformly in `HH:mm aa` (`hh:mm a`), and automatically optimizes the pricing breakdown to use the best tiered rate,  
**So that** I can easily discover availability, avoid booking overlaps, plan future reservations accurately, and always receive the most cost-effective pricing tier automatically.

### Acceptance Criteria Matrix

| AC ID | Scenario | Given | When | Then (Expected Outcome) | Verification |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-CAL-01** | Persistent Calendar Visualizer & Visual Date States | User is configuring vehicle or property rental options | Calendar is displayed on screen | The full month calendar acts as a real-time schedule visualizer with **non-clickable day cells** (preventing accidental date overrides) and **interactive month navigation** (`<` / `>`). Date visual states: **Available** (standard background), **Unavailable / Reserved** (red badge/bg), **Selected Start Date** (solid brand purple with distinct active ring), **Computed Active Span** (lavender/purple connecting range band), **Selected End Date** (solid brand purple badge), **Past Dates** (dimmed). | `packages/tranyx_web` & `packages/tranyx_mobile` |
| **AC-CAL-02** | Dedicated Start Date & End Date Pickers with Bi-directional Sync | User is on the booking modal | User interacts with Start Date or End Date date picker inputs (`<input type="date">`), or adjusts the Duration Stepper / Multiplier | System supports flexible future start date selection and allows picking any End Date (e.g. 2 days, 5 days, 10 days). Changing Start/End Date automatically recalculates `_quantity` and updates the calendar highlight band. Changing `_quantity` automatically updates the End Date picker value. | `packages/tranyx_web` & `packages/tranyx_mobile` |
| **AC-CAL-03** | Span Conflict & Overlap Detection | User configures a start date and duration | Range $[\text{Start Date}, \text{End Date}]$ passes through or lands on any reserved (red) date | Overlapping dates pulse with red warning border (`border-2 border-red-500 bg-red-500/30`), an inline warning alert displays: *"Selected duration overlaps with an existing reservation on [Conflicting Date(s)]. Please choose a different start date or shorter duration."*, and the Confirm / Proceed CTA is disabled. | `packages/tranyx_web` & `packages/tranyx_mobile` |
| **AC-CAL-04** | 7-Day Weekly Threshold Optimization | Vehicle has daily rate ₱1,000 and weekly rate ₱4,500 | User selects 7 days duration | `SmartRateEngine` automatically switches base pricing to 1x Weekly Rate (₱4,500) instead of 7x daily (₱7,000), saving ₱2,500. | `packages/shared/lib/src/smart_rate_engine.dart` & `smart_rate_engine_test.dart` |
| **AC-CAL-05** | 30-Day Monthly Threshold Optimization | Vehicle/Property has monthly rate ₱16,000 | User selects 30 days duration | `SmartRateEngine` automatically switches base pricing to 1x Monthly Rate (₱16,000) instead of daily/weekly accumulators. | `packages/shared/lib/src/smart_rate_engine.dart` & `smart_rate_engine_test.dart` |
| **AC-CAL-06** | Hybrid Duration Decomposition | User selects 10 days duration with daily ₱1,000 and weekly ₱4,500 | Pricing is computed | Engine optimizes breakdown to $(1 \times \text{Weekly Rate}) + (3 \times \text{Daily Rate}) = \text{₱}7,500$ and displays breakdown text: `"1 x Weekly (₱4,500) + 3 x Daily (₱3,000)"`. | `packages/shared/lib/src/smart_rate_engine.dart` & `smart_rate_engine_test.dart` |
| **AC-CAL-07** | Price Capping Rule | Daily rate is ₱1,000 and flat weekly rate is ₱4,500 | User selects 5 days ($5 \times 1,000 = \text{₱}5,000 > \text{₱}4,500$) | Engine automatically caps price at cheaper Weekly Rate (₱4,500), shows optimization pill: `"✨ Optimal 1-Week Cap Applied"`, and saves ₱500. | `packages/shared/lib/src/smart_rate_engine.dart` & `smart_rate_engine_test.dart` |
| **AC-CAL-08** | Time Format Uniformity (`HH:mm aa` / `hh:mm a`) & Schedule Summary Parity | User views any schedule timestamp, time dropdown, summary box, or contract receipt | Time is rendered | All timestamps are formatted in 12-hour format with zero-padded 2-digit hours, minutes, and AM/PM markers (e.g. `Starts: Aug 25, 2026 • 09:00 AM`, `Ends: Aug 27, 2026 • 09:00 AM`). Payload assigns exact epoch milliseconds (`startDate`, `endDate`). | `packages/tranyx_web` & `packages/tranyx_mobile` |
| **AC-CAL-09** | Unavailable / Unoffered Package Option Locking | Listing does not configure a specific package (e.g. `price12h == 0` or `priceMonthly == 0`) | User views "Select Rental Package" options | Unoffered packages render with dimmed opacity (`opacity-40 cursor-not-allowed`), display an `"Unavailable"` / `"Not Offered"` badge, and cannot be clicked or selected. Initialization automatically defaults to the first available package rate. | `packages/tranyx_web` & `packages/tranyx_mobile` |

---

## 7. Dynamic & Immutable Counterparty Identity Verification in Contracts & Summaries (`AC-KYC-01` to `AC-KYC-04`)

| AC ID | Feature / Scenario | Given | When | Then / Expected Outcome | Verified File(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-KYC-01** | Unverified User in Generated Contract | User with `verificationStatus == 'UNVERIFIED'`, `idVerified != true`, or `verificationLevel < 2` initiates or accepts a rental | Rental contract is drafted/generated (PDF or on-screen agreement) | Party identification explicitly states: `"Identity Status: Unverified Account"`, styled in subtle amber/zinc without verified badges, checkmark icons, or misleading certified labels. | `contract_viewer.dart`, `contract_drafts.dart`, `PartyVerificationHelper` |
| **AC-KYC-02** | Verified User with KYC in Generated Contract | User with completed KYC (`verificationStatus == 'VERIFIED'`, `idVerified == true`, or `verificationLevel >= 2`) | Rental contract is generated or signed | Party details specify exact verification tier: `"Identity Status: Verified (Government ID Verified)"` (or `"Level 3 Pro Verified"`), accompanied by verified green shield/checkmark badges. | `contract_viewer.dart`, `contract_drafts.dart`, `PartyVerificationHelper` |
| **AC-KYC-03** | Universal Transaction Views & Receipts | Any transaction summary (Rental Booking Details, Job Acceptance, Escrow Receipt, Booking Modal Step 2) | Party information is rendered | Accurately reflects real-time database state: Verified users show tier badges (`Government ID Verified`), and Unverified users display explicit `"Unverified"` indicator without trust badges. | `book_vehicle_modal.dart`, `book_property_modal.dart`, `PartyVerificationHelper` |
| **AC-KYC-04** | Immutable Contract Snapshot | A rental/lease contract is signed and executed | Contract document is saved | Creates a permanent frozen snapshot in `/rental_contracts/{contractId}` capturing `hostIsVerified`, `hostVerificationStatus`, `hostVerificationTier`, `renteeIsVerified`, `renteeVerificationStatus`, `renteeVerificationTier`, `signatureHash`, and `signedAt`, preventing retroactive mutation. | `firebase_service.dart`, `VehicleRental`, `PropertyRental`, `party_verification_test.dart` |

---

## 8. LTO Registration & Comprehensive Insurance Compliance Form Integration (`AC-LTO-01` to `AC-LTO-04`)

| AC ID | Feature / Scenario | Given | When | Then / Expected Outcome | Verified File(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-LTO-01** | Host Inputs LTO CR & OR Numbers | Host lists a vehicle on Web (`list_vehicle_modal.dart`) or Mobile (`listing_wizard_sheet.dart`) | Host enters LTO Certificate of Registration (CR) and Official Receipt (OR) numbers in Step 1 | Values are bound to `_ltoCrNumber` and `_ltoOrNumber`, sanitized/uppercased, saved in Firestore, and rendered in Section 3 of generated contracts instead of hardcoded `'PENDING'`. | `list_vehicle_modal.dart`, `listing_wizard_sheet.dart`, `contract_viewer.dart` |
| **AC-LTO-02** | Comprehensive Insurance Provider & Policy Reference | Host configures insurance coverage | Host selects insurance provider from standard Philippine providers (Standard, Malayan, FPG, Pioneer, Mercantile, Alpha, Charter Ping An, or N/A/CTPL) and inputs Policy Reference Number | Values are saved to `insuranceProvider` and `insurancePolicyNumber`, and displayed in Section 3 of P2P agreements instead of `'N/A'`. | `list_vehicle_modal.dart`, `listing_wizard_sheet.dart`, `contract_viewer.dart` |
| **AC-LTO-03** | Insured Vehicle Market Value (TYXBIT / PHP) | Host defines vehicle valuation | Host fills out Insured Market Value (₱) | Value is parsed and formatted as `vehicleValue` in TYXBIT / PHP and reflected in Section 2 (Vehicle Specifications) of the contract. | `list_vehicle_modal.dart`, `listing_wizard_sheet.dart`, `contract_viewer.dart` |
| **AC-LTO-04** | Contract Preview Parity in Wizard | Host clicks "View Contract" in Step 4 before submitting | Listing wizard renders contract preview | Embedded `ContractViewerComponent` previews the exact LTO CR, OR, Insurance Provider, Policy Reference, and Insured Value entered during Step 1. | `list_vehicle_modal.dart`, `listing_wizard_sheet.dart`, `contract_viewer.dart` |

---

## 9. Transparent Gig Filtering Controls & Live Active Summary Strip (`AC-GIG-01` to `AC-GIG-10`)

| AC ID | Feature / Scenario | Given | When | Then / Expected Outcome | Verified File(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-GIG-01** | Default Filter State | Nyxian navigates to Browse Gigs | Page or screen loads | Default filters: Category = `"All"`, Distance = `"Any Distance"` (`9999.0`), Remote = `true`. Live Summary Strip shows: `"All Available Gigs • Any Distance • Remote Gigs Included (N gigs found)"`. | `gig_filter_engine.dart`, `jobs_view.dart`, `job_list_view.dart` |
| **AC-GIG-02** | Remote Only Filter Active | Nyxian toggles Remote Gigs ON, sets Distance = `"Within 15 km"` | Feed evaluates gig pool | Remote gigs (`is_remote: true`) bypass physical distance and are included. On-site gigs within 15 km are included; on-site gigs > 15 km are excluded. | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |
| **AC-GIG-03** | Remote Excluded (Remote OFF) | Nyxian toggles Remote Gigs OFF | Feed evaluates gig pool | Remote gigs (`is_remote: true`) are strictly excluded regardless of category or distance. Only on-site gigs matching the distance radius are evaluated. | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |
| **AC-GIG-04** | Strict Geofence Radius (On-Site) | Nyxian sets Distance = `"Within 5 km"` with Remote ON | Feed evaluates gigs | On-site gig at 3.2 km is included. On-site gig at 7.8 km is excluded. Remote gig is included (bypasses distance). | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |
| **AC-GIG-05** | Recommended Category Match | Nyxian selects `"Recommended"` category filter with profile skills `["Plumbing", "Welding"]` | Feed evaluates categories | Gigs whose title, description, or category match user skills are included. Non-matching gigs are excluded. | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |
| **AC-GIG-06** | High Paying Category Match | Nyxian selects `"High Paying"` category filter | Feed evaluates pricing | Gigs with `pricingValue >= 1000.0` (or `payout >= 1000.0`) are included. Gigs with `payout < 1000.0` are excluded. | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |
| **AC-GIG-07** | Combined Filtering Matrix | Nyxian sets Category = `"High Paying"`, Distance = `"Within 30 km"`, Remote = `false` | Feed evaluates formula $\text{Match} = \text{Category Rule} \land \text{Distance Rule}$ | Only on-site gigs within 30 km with payout $\ge 1000.0$ are included. Remote gigs and low-paying gigs are excluded. | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |
| **AC-GIG-08** | Live Active Filter Summary Strip | Any filter combination is active | Summary strip renders above gig cards | Displays real-time breakdown with bold category, bullet-separated distance/modality, and accurate result count: `"[Category] • [Distance] • [Modality] (X gigs found)"` with `"Clear All"` button when non-default. | `gig_filter_engine.dart`, `jobs_view.dart`, `job_list_view.dart` |
| **AC-GIG-09** | Zero Results State & Reset CTA | Filters yield zero matching gigs | Empty state is rendered | Displays `"No available gigs match your current filters"`, maintains the active summary strip showing `(0 gigs found)`, and provides a prominent `"Reset Filters"` CTA button returning to defaults. | `jobs_view.dart`, `job_list_view.dart` |
| **AC-GIG-10** | Client-Side Pure Dart Filtering | Multiple gigs fetched from Firebase Firestore DB | Filter conditions change | Pure client-side filtering executed via `GigFilterEngine.filterGigList` without calling Cloud Functions. | `gig_filter_engine.dart`, `gig_filter_engine_test.dart` |

---

## 10. Role-Based Search Bar Exclusivity (`AC-SEARCH-01`)

| AC ID | Feature / Scenario | Given | When | Then / Expected Outcome | Verified File(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-SEARCH-01** | Search Exclusively for Nyxians (Job Seekers) | User is logged in as Employer or Nyxian on Web or Mobile | Home / Dashboard screen is rendered | Global search bar and inputs are rendered **only** when `isNyxian == true` (Nyxian mode). In Employer mode (`currentViewMode == AccountType.employer`), search input is completely removed so employers focus on posting jobs. | `home_view.dart` (Web), `home_view.dart` (Mobile), `jobs_view.dart` (Web) |

---

---

## 11. Interactive Walkthrough & Verification Badge System (`AC-ONBOARD-01` to `AC-ONBOARD-05`)

| AC ID | Feature / Scenario | Given | When | Then / Expected Outcome | Verified File(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-ONBOARD-01** | First-Time Launch Auto-Trigger | User opens app for the first time or completes registration | Home screen initializes | `InteractiveWalkthroughOverlay` launches automatically with dimmed scrim and live spotlight highlight; persistent flag `has_seen_onboarding = true` is saved in `SecureStorageHelper` so it never auto-triggers again. | `main_wrapper.dart`, `secure_storage_helper.dart`, `interactive_walkthrough_overlay.dart` |
| **AC-ONBOARD-02** | Walkthrough Slide Flow & Core Modules | Walkthrough is active | User taps "Next" or swipes | Sequentially highlights 4 core platform pillars: 1. Trust & Verification Badges, 2. Rentals & Calendar Availability, 3. Jobs & Live Execution Tracking, 4. MWA Web3 Wallet & GCash/Token Ledger. | `interactive_walkthrough_overlay.dart`, `user_badge_and_walkthrough_test.dart` |
| **AC-ONBOARD-03** | Visual Verification Badges on Profile & Counterparty Cards | Verified Level 1 or Level 2 user profile | Profile header, listing owner card, or contractor card renders | Level 1 renders distinct Cyan badge (`VERIFIED`); Level 2 renders upgraded Gold shield badge (`PRO`); tapping opens a bottom sheet modal detailing Gov ID, Biometrics, and Merchant/Business records. | `user_badge_widget.dart` (Mobile), `user_badge_component.dart` (Web), `profile_view.dart` |
| **AC-ONBOARD-04** | Zero Badges for Unverified Users | User is unverified (`verificationLevel == VerificationLevel.none`) | Any user profile, transaction summary, or card renders | Renders `SizedBox.shrink()` (0 badge icons, zero misleading certified labels). | `user_badge_widget.dart`, `user_badge_component.dart`, `user_badge_and_walkthrough_test.dart` |
| **AC-ONBOARD-05** | Walkthrough Dismissal & Profile Replay | User is anywhere in the app | User dismisses walkthrough or clicks "App Guide & Verification Levels" in Profile/Help | "Close" (X) or outside tap immediately dismisses walkthrough. On-demand replay is always available in Settings > Help & Support > App Guide & Verification Levels. | `profile_view.dart`, `interactive_walkthrough_overlay.dart`, `user_badge_and_walkthrough_test.dart` |

---

## 12. Automated Test Commands for QA Agents

```bash
# 1. Run all Shared package tests (SmartRateEngine, GigFilterEngine, AI Service, Prompt Tuning, Profanity Filter, Party Verification)
cd /Users/zeuscajurao/Desktop/tranyx_workspace/packages/shared && dart test

# 2. Run all Mobile package tests (Job Repository, Transit Repository, AI Draft Bottom Sheet, Solana Auth, Badges & Walkthrough)
cd /Users/zeuscajurao/Desktop/tranyx_workspace/packages/tranyx_mobile && flutter test

# 3. Run Static Analysis across the entire workspace
cd /Users/zeuscajurao/Desktop/tranyx_workspace && dart analyze packages/shared packages/tranyx_web
cd /Users/zeuscajurao/Desktop/tranyx_workspace && flutter analyze packages/tranyx_mobile
```







