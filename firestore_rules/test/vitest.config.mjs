// Kelvin's Firestore rules security suite (vitest). Lives beside Saga's node:test smoke test.
// Files are vitest/*.spec.mjs so `node --test` (npm test) never picks them up.
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    include: ['vitest/**/*.spec.mjs'],
    fileParallelism: false, // one emulator, clearFirestore between tests
    testTimeout: 20000,
    hookTimeout: 30000,
    reporters: ['verbose'],
  },
});
