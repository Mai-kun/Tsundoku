import { fileURLToPath } from "node:url";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig, type PluginOption } from "vite";
import { visualizer } from "rollup-plugin-visualizer";

// Local assets are served by the API, not by Vite. Point the proxy at the test
// backend with MT_API_TARGET=http://localhost:5001 when it runs on another port.
const apiTarget = process.env.MT_API_TARGET ?? "http://localhost:5000";

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    svelte(),
    tailwindcss(),
    visualizer({
      filename: "../reports/bundle-stats.html",
      template: "treemap",
      gzipSize: true,
      brotliSize: true,
    }) as PluginOption,
    visualizer({
      filename: "../reports/bundle-stats.json",
      template: "raw-data",
      gzipSize: true,
      brotliSize: true,
    }) as PluginOption,
  ],
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
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("node_modules")) {
            return "vendor";
          }
        },
      },
    },
  },
  server: {
    proxy: {
      "/api": apiTarget,
      // Covers are served by the API from its data directory, not from public/.
      // Without this the SPA fallback returns index.html with a 200 and every
      // poster silently renders as broken.
      "/covers": apiTarget,
      // Same story for locally downloaded originals (/media-assets/<id>/cover/...).
      "/media-assets": apiTarget,
    },
  },
});
