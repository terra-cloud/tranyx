#!/usr/bin/env node
// Thin launcher — dependencies live under firestore_rules/test/node_modules.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const testDir = resolve(root, 'firestore_rules/test');
const script = resolve(testDir, 'kan136_claims_scout.mjs');
const r = spawnSync(process.execPath, [script], { cwd: testDir, stdio: 'inherit', env: process.env });
process.exit(r.status ?? 1);
