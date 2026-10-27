import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      $app: fileURLToPath(new URL("./src/app", import.meta.url)),
      $shared: fileURLToPath(new URL("./src/shared", import.meta.url)),
      $entities: fileURLToPath(new URL("./src/entities", import.meta.url)),
      $features: fileURLToPath(new URL("./src/features", import.meta.url)),
      $widgets: fileURLToPath(new URL("./src/widgets", import.meta.url)),
      $views: fileURLToPath(new URL("./src/views", import.meta.url)),
    },
  },
  test: {
    include: ["src/**/*.test.ts"],
    coverage: {
      provider: "v8",
      reporter: ["json-summary", "cobertura", "text"],
      reportsDirectory: "../reports/coverage/frontend",
      include: ["src/**/*.ts"],
      exclude: ["src/**/*.d.ts", "src/**/*.test.ts"],
    },
  },
});
