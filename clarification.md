# Clarification, Report, and Implementation Plan

This document outlines our understanding of the requirements, our analysis of the codebase, and the plan for integrating Trust Wallet authentication and supporting USDT transfers.

---

## 1. Trust Wallet Authentication (Sign In with Solana Wallet) [COMPLETED]

### Current Issue
When attempting to connect or sign in with Trust Wallet in the Login view, the interface always displays **"Install"** instead of **"Connect"** (even when installed), and the connection process does not trigger the correct authentication/signing flow.

### Analysis & Cause
1. **Detection Scheme Mismatch**: In `login_view.dart`, `_isWalletInstalled` only queries `wallet.nativeScheme` (which for Trust Wallet is `trust://`). Many mobile operating systems do not resolve `trust://` without a path/parameter, returning `false` for `canLaunchUrl`. In the topup/deposit tab (`payment_pane.dart`), the app correctly probes multiple alternate schemes (e.g. `trust://wc`, `trustwallet://wc`, etc.) defined in `candidateConnectSchemes`.
2. **Missing WalletConnect/AppKit Integration**: The Phantom and Solflare NaCl protocol is used for *all* wallets in `login_view.dart` via `phantomService.generateConnectUri`. Trust Wallet utilizes WalletConnect (via `ReownAppKitModal`), which doesn't support the NaCl encryption deep-link protocol.
3. **No Connection Handler in Auth View**: There is no `ReownAppKitModal` implementation or callback listener for Trust Wallet login in `login_view.dart`.

### Solution Plan (Do not touch connection functions)
* Update `_isWalletInstalled` in `login_view.dart` to probe all alternate `candidateConnectSchemes` in addition to the `nativeScheme`. [DONE]
* Integrate `ReownAppKitModal` inside `login_view.dart` specifically for the Trust Wallet path, identical to how it's initialized in `payment_pane.dart`. [DONE]
* Upon a successful `onModalConnect` event, retrieve the wallet address and perform the login/linking logic locally (similar to the deep-link route `/onConnect` in `app_router.dart`). [DONE]

---

## 2. Solana USDT Transfer (Token Program Integration) [COMPLETED]

### Current Status
* SOL deposits work via direct System Program transfers.
* USDT deposits are disabled on mobile with a warning: *"USDT deposits are web-only on mobile devices. Please select SOL or GCash/Card instead."*

### Analysis & Requirements
* **USDT Mint Address**:
  - **Mainnet**: `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` (Decimals: 6)
  - **Devnet / Testnet**: Circle USDC devnet proxy `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU` (Decimals: 6) used as a stand-in for USDT.
* **SPL Token Transfer Protocol**:
  1. Derive the sender's Associated Token Account (ATA) and recipient's (treasury's) ATA using the Solana Associated Token Account Program derivation algorithm.
  2. Check if the recipient's ATA exists on-chain using `getAccountInfo` RPC.
  3. If it doesn't exist, append a `createAssociatedTokenAccount` instruction.
  4. Append the SPL `transfer` instruction (transferring the specified micro-USDT amount).
  5. Serialize the compiled message bytes for signing.

### Implementation Plan
* **ATA Derivation**: We implemented pure-Dart Associated Token Account (ATA) derivation matching Solana's `findProgramAddress` algorithm. [DONE]
* **USDT Transfer Serialization**: We implemented a function `serializeTokenTransferTransaction` in `PhantomService` (inside `phantom_provider.dart`). [DONE]
* **Enable USDT on Mobile**:
  - Lifted the web-only restriction in `payment_pane.dart`. [DONE]
  - Wired up USDT token transfer transactions for Phantom, Solflare, and Trust Wallet (Trust Wallet uses `ReownAppKitModal.request('solana_signTransaction')` with the base64-serialized transaction, while Phantom/Solflare use the NaCl URL scheme). [DONE]
  - Verified confirmation and credited the user's TYX balance in Firestore accordingly. [DONE]

---

## 3. Solana & USDT Withdrawals (Adaptive Choice) [COMPLETED]

### Design Choice
We implemented **Option B — Adaptive Choice**, allowing users to choose whether to receive their payout in **SOL** or **USDT** at withdrawal time. Both options are funded by the system's treasury key stored in Firestore.

### Implementation Details
* Added `signAndBroadcastTokenTransfer` to `PhantomService` to support signing and broadcasting SPL Token (USDT) transfers on-chain programmatically using the treasury's private key.
* Redesigned the withdrawal action in `payment_pane.dart` to open a beautiful, modern **Stateful Bottom Sheet**:
  - Displays the user's current PHP-equivalent withdrawable balance.
  - Displays options for **Solana (SOL)** and **Tether (USDT)** side-by-side with real-time exchange rates.
  - Dynamically calculates the estimated payout amount and a 2% platform fee for the chosen asset.
  - Automatically handles Associated Token Account (ATA) creation if the recipient does not have a USDT token account yet.
  - On-chain confirmation is tracked in real-time, and transaction/platform fee history is saved to Firestore.

