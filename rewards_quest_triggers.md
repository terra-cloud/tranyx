# Tranyx Rewards & Quest Triggers Reference

This document outlines the list of available rewards in the Tranyx Quest System, their reward values, limits, and how they are triggered/completed in the codebase.

---

## 1. Onboarding Milestones

Onboarding rewards are checked and awarded in the background when the user visits the rewards page, or dynamically when specific profile conditions are updated. The logic is defined in `checkAndAwardOnboardingQuests`.

| Quest ID | Quest Name / Title | Category | Points | Limit | Trigger Condition |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`register_account`** | Register Account | Onboarding | 500 TP | Once | Awarded automatically once the user's document exists in Firestore (user is registered). |
| **`verify_account`** | Verify Account | Onboarding | 500 TP | Once | Awarded when both `emailVerified` and `phoneVerified` are `true` on the user profile. |
| **`complete_profile_trust`** | Complete Profile Trust and Verification | Onboarding | 2000 TP | Once | Awarded when `idVerified` is `true` (Identity Verification Level 2 complete). |
| **`add_skills_bio`** | Add Skills & Bio | Onboarding | 100 TP | Once | Awarded when the user has added skills (non-empty list) OR has written a headline/bio. |
| **`deposit_any_amount`** | Deposit any amount to Wallet | Onboarding | 500 TP | Once | Triggered via `awardPointsIfEligible` in the deposit flow inside `transit_repository.dart` once a wallet deposit transaction succeeds. |
| **`connect_solana_wallet`** | Connect Any Solana Wallet | Onboarding | 200 TP | Once | Awarded when the user links a Solana wallet (`walletPublicKey` is present). |

---

## 2. Service Activities

Service rewards are triggered dynamically during job posting, hiring, and completion workflows.

| Quest ID | Quest Name / Title | Category | Points | Limit | Trigger / Code Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`post_first_service`** | Post First Service | Services | 500 TP | Once | Triggered when posting a job in `firebase_service.dart` (Web). |
| **`hire_applicant`** | Hire an Applicant | Services | 500 TP | Once | Triggered when hiring an applicant in `tranyx_app.dart` (Web). |
| **`employer_complete_transaction`** | Complete transaction as employer | Services | 500 TP | Unlimited | Triggered when a service transaction is marked complete by the Employer in `tranyx_app.dart` (Web). |
| **`apply_first_job`** | Apply First Job | Services | 500 TP | Once | Triggered when a jobseeker applies for a job in `firebase_service.dart` (Web). |
| **`be_hired`** | Be hired | Services | 500 TP | Once | Triggered when a jobseeker's application is accepted in `tranyx_app.dart` (Web). |
| **`jobseeker_complete_transaction`** | Complete transaction as Nyxian | Services | 500 TP | Unlimited | Triggered when a service transaction is marked complete by the Jobseeker (Nyxian) in `tranyx_app.dart` (Web). |

---

## 3. Rental Activities

Rental rewards are triggered dynamically during listing creation, booking, and transaction completion workflows.

| Quest ID | Quest Name / Title | Category | Points | Limit | Trigger / Code Location |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`post_property`** | Post Property | Rental | 500 TP | Unlimited | Triggered when hosting a new listing (vehicle/property) in `transit_repository.dart` (Mobile). |
| **`host_complete_transaction`** | Complete Transaction as a Lessor/Host | Rental | 500 TP | Unlimited | Triggered when a lessor/host successfully completes a transaction in `transit_repository.dart` (Mobile). |
| **`rent_property`** | Rent property | Rental | 500 TP | Unlimited | Triggered when a renter initiates a booking for a vehicle or property in `transit_repository.dart` (Mobile). |
| **`client_complete_transaction`** | Complete transaction as a Lessee/Renter | Rental | 500 TP | Unlimited | Triggered when a renter/lessee successfully completes a transaction in `transit_repository.dart` (Mobile). |

---

## Summary of How it Works Under the Hood

### 1. Verification Checking (`checkAndAwardOnboardingQuests`)
Runs whenever a user goes to the rewards page to evaluate if any onboarding steps were newly accomplished.
* **On Web**: Queries the user document and writes rewards to the DB.
* **On Mobile**: Now uses a real-time `StreamProvider` for `userProfileProvider`, meaning any completed rewards synchronize and reflect instantly in the UI.

### 2. Event-Driven Crediting (`awardPointsIfEligible`)
For repeatable or transactional events (like completing a transaction or renting a property), the points are calculated and added to the user's `terraPoints` field and logged in the `points_history` collection immediately upon action completion.
