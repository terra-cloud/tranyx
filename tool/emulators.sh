#!/usr/bin/env bash
# Start local Firebase emulators (auth, firestore, storage) for project demo-tranyx.
# demo-* project ids are offline-only: the SDKs/CLI can never reach real Firebase resources.
# Data persists in .emulator-data/ (gitignored) between runs.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA_DIR=".emulator-data"
ARGS=(--project demo-tranyx --only auth,firestore,storage --export-on-exit "$DATA_DIR")
# --import fails on an empty dir, so only import once a previous export exists.
if [[ -f "$DATA_DIR/firebase-export-metadata.json" ]]; then
  ARGS+=(--import "$DATA_DIR")
fi

exec firebase emulators:start "${ARGS[@]}"
