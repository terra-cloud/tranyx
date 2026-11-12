import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { liveTargetError } from './live_target.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function cleanEnv() {
  const env = { ...process.env };
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  delete env.TARGET_GOOGLE_APPLICATION_CREDENTIALS;
  delete env.ADMIN_GOOGLE_APPLICATION_CREDENTIALS;
  return env;
}

test('prod apply without --allow-prod is refused', () => {
  const message = liveTargetError({
    apply: true, allowProd: false, project: 'tranyx-app', host: '', credPath: '/tmp/sa.json',
  });
  assert.match(message, /without --allow-prod/);
});

test('prod apply with the flag still needs a service account', () => {
  const message = liveTargetError({
    apply: true, allowProd: true, project: 'tranyx-app', host: '', credPath: '',
  });
  assert.match(message, /service account/);
});

test('prod apply is allowed only with the flag and a credential path', () => {
  const message = liveTargetError({
    apply: true, allowProd: true, project: 'tranyx-app', host: '', credPath: '/tmp/sa.json',
  });
  assert.equal(message, '');
});

test('tranyx-dev and tranyx-uat cannot take a live write', () => {
  assert.match(liveTargetError({
    apply: true, allowProd: true, project: 'tranyx-dev', host: '', credPath: '/tmp/sa.json',
  }), /Live --apply requires/);
  assert.match(liveTargetError({
    apply: true, allowProd: true, project: 'tranyx-uat', host: '', credPath: '/tmp/sa.json',
  }), /tranyx-uat/);
});

test('emulator apply does not need --allow-prod', () => {
  assert.equal(liveTargetError({
    apply: true, allowProd: false, project: '', host: '127.0.0.1:8189', credPath: '',
  }), '');
});

function runTool(script, args) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: root,
    env: cleanEnv(),
    encoding: 'utf8',
  });
}

for (const script of [
  'tool/sync_staff_claims.mjs',
  'tool/migrate_listing_locations.mjs',
  'tool/purge_job_completion_codes.mjs',
  'tool/backfill_public_profiles.mjs',
]) {
  test(`${script} refuses tranyx-app --apply without --allow-prod`, () => {
    const result = runTool(script, ['--project', 'tranyx-app', '--apply']);
    assert.notEqual(result.status, 0);
    assert.match(`${result.stderr}${result.stdout}`, /allow-prod/);
  });

  test(`${script} refuses tranyx-app --allow-prod --apply without a service account`, () => {
    const result = runTool(script, ['--project', 'tranyx-app', '--allow-prod', '--apply']);
    assert.notEqual(result.status, 0);
    assert.match(`${result.stderr}${result.stdout}`, /service account/);
  });
}
