# Local Firebase emulators

Auth, Firestore and Storage run locally under project id **`demo-tranyx`**.
The `demo-` prefix tells the Firebase CLI and SDKs the project is offline-only, so
nothing here can read, write or deploy to `tranyx-dev`, `tranyx-uat` or `tranyx-app`.
Never use `firebase deploy` with these commands.

Requires Firebase CLI, Java 21+ and Node 22.

## Start

```sh
tool/emulators.sh
```

- Emulator UI: http://localhost:4000
- Ports: auth 9099, firestore 8080, storage 9199
- Data persists in `.emulator-data/` (gitignored): exported on exit (Ctrl+C), imported on next start.
  Delete the folder for a clean slate.
- Firestore uses the compiled `firestore.rules` (`dart run tool/build_rules.dart`).
  There is no `storage.rules` yet, so the Storage emulator runs with default open rules.

## Seed test users

With the emulators running, in another terminal:

```sh
npm install --prefix firestore_rules/test   # first time only
npm run seed --prefix firestore_rules/test
```

All accounts are test-only, password `test-only-password`:

| uid | email | privilege |
| --- | --- | --- |
| `owner` | owner@example.test | normal user |
| `staff` | staff@example.test | custom claim `role: 'staff'` |
| `admin` | admin@example.test | custom claim `admin: true` |
| `attacker` | attacker@tranyx.com (unverified) | no claims; `users/attacker` has `isAdmin`, `isP2pAgent`, `role: 'admin'` |

`guest` has no account: tests use an unauthenticated context.
Re-running the seed recreates these users.

## Run the rules tests

```sh
firebase emulators:exec --project demo-tranyx --only firestore "npm test --prefix firestore_rules/test"
```

Tests live in `firestore_rules/test/*.test.js` (Node's built-in `node:test` + `@firebase/rules-unit-testing`).
`tool/build_rules.dart` only compiles top-level `firestore_rules/*.rules`, so the test folder doesn't affect the rules build.
