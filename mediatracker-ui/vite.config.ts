import { fileURLToPath } from "node:url";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte(), tailwindcss()],
  resolve: {
    alias: {
      $lib: fileURLToPath(new URL("./src/lib", import.meta.url)),
    },
  },
  build: {
    outDir: "../src/MediaTracker.Server/wwwroot",
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
