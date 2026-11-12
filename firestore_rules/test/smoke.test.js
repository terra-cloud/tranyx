// Smoke test: proves the emulator + compiled firestore.rules load and evaluate.
// Run: firebase emulators:exec --project demo-tranyx --only firestore "npm test --prefix firestore_rules/test"
const { test, before, after } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tranyx',
    firestore: {
      // Compiled output of tool/build_rules.dart; never edit it directly.
      rules: fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8'),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'jobs/smoke-job'), { title: 'Smoke job', status: 'Open' });
  });
});

after(async () => {
  await env?.cleanup();
});

test('unauthenticated guest can read a doc in jobs', async () => {
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, 'jobs/smoke-job')));
});
