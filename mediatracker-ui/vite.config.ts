import { fileURLToPath } from "node:url";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte(), tailwindcss()],
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
  build: {
    outDir: "../MediaTracker.Server/wwwroot",
    emptyOutDir: true,
  },
  server: {
    proxy: {
      "/api": "http://localhost:5000",
      // Covers are served by the API from its data directory, not from public/.
      // Without this the SPA fallback returns index.html with a 200 and every
      // poster silently renders as broken.
      "/covers": "http://localhost:5000",
    },
  },
});
