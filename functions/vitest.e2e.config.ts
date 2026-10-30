import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { include: ['test-e2e/**/*.e2e.ts'], fileParallelism: false, testTimeout: 60000, hookTimeout: 60000, reporters: ['verbose'] } });
