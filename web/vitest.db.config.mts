import { defineConfig } from "vitest/config";
import path from "node:path";

// Integration tests against a running local Supabase (`npm run db:start`).
export default defineConfig({
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "src") } },
  test: {
    include: ["tests/db/**/*.test.ts"],
    environment: "node",
    testTimeout: 30000,
    fileParallelism: false,
  },
});
