import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DEFAULT_ADMIN_PROJECT_ID, planStaffClaims, staffClaimsFor } from './staff_claims_plan.mjs';
import { applyStaffClaimPlan, collectStaffClaimPlan } from './sync_staff_claims.mjs';

test('default admin project is tranyx-admin-portal', () => {
  assert.equal(DEFAULT_ADMIN_PROJECT_ID, 'tranyx-admin-portal');
});

test('admin and superadmin claims outrank staff', () => {
  assert.deepEqual(staffClaimsFor({ isAdmin: true }), { admin: true, role: 'admin' });
  assert.deepEqual(staffClaimsFor({ isSuperAdmin: true }), { admin: true, role: 'admin' });
  assert.deepEqual(staffClaimsFor({ isStaff: true }), { admin: false, role: 'staff' });
  assert.equal(staffClaimsFor({ name: 'plain' }), null);
});

test('empty doc email resolves through admin auth and grants the target uid', () => {
  const plan = planStaffClaims({
    flagged: [{ sourceUid: 'portal-1', docEmail: '', claims: { admin: true, role: 'admin' } }],
    sourceAuthEmailByUid: new Map([['portal-1', 'Admin@Example.com']]),
    targetByEmail: new Map([['admin@example.com', { uid: 'app-9', email: 'admin@example.com', customClaims: {} }]]),
    targetUsers: [{ uid: 'app-9', email: 'admin@example.com', customClaims: {} }],
  });
  assert.deepEqual(plan.grant, [{
    uid: 'app-9', email: 'admin@example.com', sourceUid: 'portal-1', admin: true, role: 'admin',
  }]);
  assert.deepEqual(plan.unmatched, []);
  assert.equal(plan.grant.some((row) => row.uid === 'portal-1'), false);
});

test('doc email wins over the admin auth email', () => {
  const plan = planStaffClaims({
    flagged: [{ sourceUid: 'portal-1', docEmail: 'doc@example.com', claims: { admin: false, role: 'staff' } }],
    sourceAuthEmailByUid: new Map([['portal-1', 'auth@example.com']]),
    targetByEmail: new Map([['doc@example.com', { uid: 'app-2', email: 'doc@example.com', customClaims: {} }]]),
    targetUsers: [{ uid: 'app-2', email: 'doc@example.com', customClaims: {} }],
  });
  assert.equal(plan.grant[0].uid, 'app-2');
  assert.equal(plan.grant[0].email, 'doc@example.com');
});

test('missing email and missing target user are reported and never granted', () => {
  const plan = planStaffClaims({
    flagged: [
      { sourceUid: 'portal-blank', docEmail: '  ', claims: { admin: true, role: 'admin' } },
      { sourceUid: 'portal-gone', docEmail: '', claims: { admin: true, role: 'admin' } },
    ],
    sourceAuthEmailByUid: new Map([['portal-blank', ''], ['portal-gone', 'gone@example.com']]),
    targetByEmail: new Map(),
    targetUsers: [],
  });
  assert.deepEqual(plan.grant, []);
  assert.deepEqual(plan.unmatched, [
    { sourceUid: 'portal-blank', email: '', reason: 'no-email' },
    { sourceUid: 'portal-gone', email: 'gone@example.com', reason: 'no-target-user' },
  ]);
});

test('revocation keys on target users who were not matched', () => {
  const plan = planStaffClaims({
    flagged: [{ sourceUid: 'portal-1', docEmail: 'keep@example.com', claims: { admin: false, role: 'staff' } }],
    sourceAuthEmailByUid: new Map(),
    targetByEmail: new Map([['keep@example.com', {
      uid: 'app-keep', email: 'keep@example.com', customClaims: { admin: false, role: 'staff' },
    }]]),
    targetUsers: [
      { uid: 'app-keep', email: 'keep@example.com', customClaims: { admin: false, role: 'staff' } },
      { uid: 'app-old', email: 'old@example.com', customClaims: { admin: true, role: 'admin' } },
      { uid: 'app-plain', email: 'plain@example.com', customClaims: {} },
    ],
  });
  assert.deepEqual(plan.grant, []);
  assert.deepEqual(plan.wouldRevoke, [{ uid: 'app-old', email: 'old@example.com' }]);
});

test('collector asks admin auth for a blank doc email and grants the target uid', async () => {
  const sourceDb = {
    collection() {
      return { get: async () => ({ docs: [{ id: 'portal-1', data: () => ({ isAdmin: true, email: '' }) }] }) };
    },
  };
  const sourceAuth = {
    async getUser(uid) {
      assert.equal(uid, 'portal-1');
      return { uid, email: 'a@example.com' };
    },
  };
  const targetAuth = {
    async getUserByEmail(email) {
      assert.equal(email, 'a@example.com');
      return { uid: 'app-1', email, customClaims: {} };
    },
    async listUsers() {
      return { users: [{ uid: 'app-1', email: 'a@example.com', customClaims: {} }] };
    },
  };
  const plan = await collectStaffClaimPlan({ sourceDb, sourceAuth, targetAuth });
  assert.equal(plan.grant[0].uid, 'app-1');
  assert.equal(plan.grant[0].sourceUid, 'portal-1');
  assert.deepEqual(plan.unmatched, []);
});

test('apply writes claims only after the target uid exists', async () => {
  const writes = [];
  const targetAuth = {
    async getUser(uid) {
      if (uid === 'missing') {
        const error = new Error('no user');
        error.code = 'auth/user-not-found';
        throw error;
      }
      return { uid, email: 'a@example.com', customClaims: {} };
    },
    async setCustomUserClaims(uid, claims) {
      writes.push({ uid, claims });
    },
  };
  const result = await applyStaffClaimPlan({
    targetAuth,
    plan: {
      grant: [
        { uid: 'app-1', email: 'a@example.com', admin: true, role: 'admin' },
        { uid: 'missing', email: 'b@example.com', admin: true, role: 'admin' },
      ],
      wouldRevoke: [],
    },
    revoke: false,
    project: 'demo-tranyx',
  });
  assert.deepEqual(writes, [{ uid: 'app-1', claims: { admin: true, role: 'admin' } }]);
  assert.deepEqual(result.applied, ['app-1']);
});

test('two portal users with one email keep the admin claim on the target uid', () => {
  const plan = planStaffClaims({
    flagged: [
      { sourceUid: 'portal-staff', docEmail: 'same@example.com', claims: { admin: false, role: 'staff' } },
      { sourceUid: 'portal-admin', docEmail: 'same@example.com', claims: { admin: true, role: 'admin' } },
    ],
    sourceAuthEmailByUid: new Map(),
    targetByEmail: new Map([['same@example.com', { uid: 'app-1', email: 'same@example.com', customClaims: {} }]]),
    targetUsers: [{ uid: 'app-1', email: 'same@example.com', customClaims: {} }],
  });
  assert.equal(plan.grant.length, 1);
  assert.equal(plan.grant[0].uid, 'app-1');
  assert.equal(plan.grant[0].admin, true);
  assert.equal(plan.grant[0].role, 'admin');
});
