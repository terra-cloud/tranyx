# Tranyx Platform Architecture & Real-Time Tracking Blueprint

## 1. Executive Summary & Ecosystem Overview

Tranyx is a localized service bridging platform engineered specifically for the Philippine market, designed to seamlessly connect employers with skilled independent workers ("Nyxians"). To capture immediate market needs, the platform launches with two core operational verticals: **Service Bridging** (on-demand and contract labor) and **Logistics/Vehicle Rental**.

The long-term engineering roadmap establishes Tranyx as a Web3-integrated ecosystem by scaling into a real estate portal (sales and rentals) powered by proprietary utility tokens ($TYXBIT), native Solana ($SOL) integration, and non-fungible tokens (NFTs) representing platform milestones, service credentials, or digital property rights.

### Technical Stack Matrix
* **Frontend Ecosystem:** Flutter (Cross-platform Android & iOS Native Mobile Apps) paired with Jaspr (Dart-native web framework for fast, SEO-optimized Web Platforms).
* **Backend Infrastructure:** Firebase Ecosystem
    * *Database:* Cloud Firestore (NoSQL Document-Store with Real-time Listeners)
    * *Authentication:* Firebase Authentication (Phone, Email, OAuth, and Web3 Custom Auth bindings)
    * *Storage:* Firebase Storage (Secure asset and receipt repository)
    * *Analytics:* Google Analytics for Firebase (User behavior and funnel optimization)
    * *Push Notifications:* Firebase Cloud Messaging (FCM for real-time state alerts)

---

## 2. Core Service Bridging Workflow (Standard Jobs)

Applies to stationary, non-delivery tasks (e.g., appliance repair, cleaning, tutoring, remote work).
The job progresses through a simple linear state machine backed by Firestore.

```
       ┌──────────────────────┐
       │  1. Hired            │
       │     (in_progress)    │
       └──────────┬───────────┘
                  │
    [Nyxian finishes task, taps "Mark as Done"]
                  │
                  ▼
       ┌──────────────────────┐
       │  2. Done             │
       │     (done)           │
       └──────────┬───────────┘
                  │
      [Employer opens app → generates QR Code]
                  │
                  ▼
       ┌──────────────────────┐
       │  3. Verification     │
       └──────────┬───────────┘
                  │
   [Nyxian scans the QR Code OR manually enters the code]
                  │
                  ▼
       ┌──────────────────────┐
       │  4. Completed        │
       │     (completed)      │
       │  ── Escrow released  │
       │     to Nyxian ──     │
       └──────────┬───────────┘
                  │
     [Both rate each other 1–5 ★]
                  │
                  ▼
               (Done)
```

### Step-by-Step:
1. **Hired (`in_progress`):** The Employer hires a Nyxian. Payment is held in platform escrow and the job is marked active.
2. **Nyxian Marks Done (`done`):** When the task is finished, the Nyxian taps **"Mark as Done"**. The Employer receives a notification.
3. **Employer Generates QR Code:** The Employer opens the job and generates a QR code. The Nyxian then either:
   - **Scans** the QR code with their camera, or
   - **Manually enters** the code shown on the Employer's screen.
4. **Escrow Release (`completed`):** The code is verified, payment is released from escrow to the Nyxian, and the job is marked `completed`.
5. **Mutual Rating:** Both the Employer and Nyxian rate each other from **1 to 5 stars**.

---

## 3. Delivery Tracker Workflow (Delivery & Courier Jobs)

When a job's category has `hasTracker = true`, it is a **delivery job**. Instead of a single "Done" action, the Nyxian goes through multiple location-based checkpoints across two named points:
- **First Point** — the pickup or store location
- **Second Point** — the drop-off or destination (the label shown in the app is whatever the Employer named it when posting the job, e.g. "Client's Office", "Warehouse", "My House")

> ⚠️ **Important:** In delivery jobs the QR flow is **reversed** compared to standard jobs.
> - Standard: **Employer generates** QR → Nyxian scans
> - Delivery: **Nyxian generates** QR → Employer (or recipient at drop-off) scans

```
       ┌──────────────────────────────┐
       │  1. Hired / In Progress      │
       │     (in_progress)            │
       └──────────────┬───────────────┘
                      │
     [Nyxian travels to and arrives at First Point]
                      │
                      ▼
       ┌──────────────────────────────┐
       │  2. Arrived at First Point   │
       │     (arrived_pickup)         │
       └──────────────┬───────────────┘
                      │
   [Nyxian pays at the cashier, uploads receipt photo]
                      │
                      ▼
       ┌──────────────────────────────┐
       │  3. Paid Cashier             │
       │     (paid_cashier)           │
       └──────────────┬───────────────┘
                      │
   [Nyxian taps "Going to [Second Point Name]"]
                      │
                      ▼
       ┌──────────────────────────────┐
       │  4. Going to Second Point    │
       │     (in_transit)             │
       └──────────────┬───────────────┘
                      │
      [Nyxian arrives at the Second Point / Drop-off]
                      │
                      ▼
       ┌──────────────────────────────┐
       │  5. Arrived at Drop-Off      │
       │     (arrived_dropoff)        │
       └──────────────┬───────────────┘
                      │
   [Nyxian generates QR → Employer / Recipient scans it]
                      │
                      ▼
       ┌──────────────────────────────┐
       │  6. Completed                │
       │     (completed)              │
       │  ── Escrow released          │
       │     to Nyxian ──             │
       └──────────────┬───────────────┘
                      │
        [Both rate each other 1–5 ★]
                      │
                      ▼
                   (Done)
```

### Step-by-Step:
1. **Hired (`in_progress`):** The Employer hires a Nyxian for a delivery. Payment is held in escrow. The job is flagged as a delivery job via `hasTracker = true`.
2. **Arrived at First Point (`arrived_pickup`):** The Nyxian travels to the pickup/store and taps **"Arrived at First Point"**. The Employer is notified.
3. **Paid Cashier (`paid_cashier`):** The Nyxian purchases the item(s) or pays the merchant, then taps **"Paid Cashier"** and **uploads a photo of the receipt** as proof. This step is required to proceed.
4. **Going to Second Point (`in_transit`):** The Nyxian taps **"Going to [Second Point Name]"**. The label displayed is whatever name the Employer gave the drop-off location when posting the job. The Employer is notified the Nyxian is en route.
5. **Arrived at Drop-Off (`arrived_dropoff`):** The Nyxian arrives at the destination. At this stage:
   - The **Nyxian generates the QR code** on their screen.
   - The **Employer or the recipient at the drop-off scans it** to confirm the delivery was received.
6. **Escrow Release (`completed`):** The QR scan is verified, payment is released from escrow to the Nyxian, and the job is marked `completed`.
7. **Mutual Rating:** Both the Employer and Nyxian rate each other from **1 to 5 stars**.

---

## 4. Cloud Firestore Schema Blueprint

The architecture relies on high-integrity normalization within specific collections to drive seamless UI transformations across Flutter and Jaspr.

### `jobs` Collection Document Schema
```json
{
  "jobId": "JOB_98765_XYZ",
  "employerId": "USR_EMPLOYER_001",
  "nyxianId": "USR_NYXIAN_999",
  "title": "Document Courier Express",
  "description": "Deliver sensitive title deeds to real estate office.",
  "category": {
    "categoryId": "CAT_DELIVERY",
    "name": "Express Courier",
    "hasTracker": true
  },
  "status": "in_transit",
  "financials": {
    "currency": "PHP",
    "escrowAmount": 350.00,
    "reimbursementAmount": 1200.00,
    "paymentStatus": "escrowed"
  },
  "routing": {
    "firstPoint": {
      "label": "Antel Grand Clerk Office",
      "geopoint": { "_latitude": 14.3981, "_longitude": 120.8904 }
    },
    "secondPoint": {
      "label": "Cavite City Corporate Hub",
      "geopoint": { "_latitude": 14.4792, "_longitude": 120.9012 }
    }
  },
  "verification": {
    "verificationCode": "TX982A",
    "receiptUrl": "https://firebase.storage.../receipts/JOB_98765/receipt.jpg"
  },
  "timestamps": {
    "createdAt": "2026-05-19T04:00:00Z",
    "startedAt": "2026-05-19T04:15:00Z",
    "completedAt": null
  },
  "ratings": {
    "employerToNyxian": null,
    "nyxianToEmployer": null
  }
}
```

### Job Status State Machine

| Current State      | Who Acts       | Action Required                          | Next State         |
|--------------------|----------------|------------------------------------------|--------------------|
| `pending`          | Employer       | Hires a Nyxian                           | `in_progress`      |
| `in_progress`      | Nyxian         | Taps "Mark as Done" *(standard)*         | `done`             |
| `in_progress`      | Nyxian         | Taps "Arrived at First Point" *(delivery)* | `arrived_pickup` |
| `arrived_pickup`   | Nyxian         | Pays cashier + uploads receipt photo     | `paid_cashier`     |
| `paid_cashier`     | Nyxian         | Taps "Going to [Second Point Name]"      | `in_transit`       |
| `in_transit`       | Nyxian         | Arrives at drop-off location             | `arrived_dropoff`  |
| `arrived_dropoff`  | Nyxian         | Generates QR → Employer/Recipient scans  | `completed`        |
| `done`             | Employer       | Generates QR → Nyxian scans or enters code | `completed`     |
| `completed`        | Both           | Rate each other 1–5 stars                | *(closed)*         |

---

## 5. Strategic Technological Roadmap (Web3 & Feature Expansion)

As Tranyx stabilizes its market base across service bridging and vehicle procurement, the software architecture will layer decentralized utilities on top of the established Firebase backend.

```
┌────────────────────────────────────────────────────────────────────────┐
│                      PHASE 1: STABILIZATION (Current)                  │
│  - Flutter Mobile + Jaspr Web Engine                                    │
│  - Firebase Firestore Core & Local PHP Fiat Channels                   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        PHASE 2: DECENTRALIZATION                       │
│  - Core Tranyx Crypto Wallet Architecture Deployment                    │
│  - Direct Ledger Connections to Phantom Wallet Deeplinks                │
│  - Web3 Signature-Based App Authentication Custom Flows                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    PHASE 3: WEB3 REAL ESTATE INTEGRATION               │
│  - Real-Estate Listing Portal Implementation                           │
│  - Non-Custodial Smart Contract Escrows ($SOL Sales)                   │
│  - Specialized Token Utility Vault Processing ($TYXBIT Lease)          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    PHASE 4: EXPANSION & GAMIFICATION                   │
│  - NFT Verification Badges for Top-Tier Verified Nyxians               │
│  - Fractional Digital Real Estate Tokenization Protocol                │
└────────────────────────────────────────────────────────────────────────┘
```

### Future Architectural Specifications:

**Tranyx Wallet Integration:** Native non-custodial wallet managed on-device via Flutter secure storage, with direct bridging to Phantom Wallet via Solana deep-linking standards.

**Decentralized Real-Estate Ledger:**
- *Purchases:* Conducted via Web3 transaction layers using Solana ($SOL) through automated smart contracts.
- *Leases/Rentals:* Programmed exclusively via $TYXBIT, enabling automated lease tracking and programmatic payment distribution.

**NFT Marketplace Engine:** Verifiable Solana-based compressed NFTs (cNFTs) serving as work history markers, reward vectors, property deed representations, and service accreditation passports.