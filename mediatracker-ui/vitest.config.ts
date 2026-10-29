import { fileURLToPath } from "node:url";
import fs from "node:fs";
import { defineConfig } from "vitest/config";
import esbuild from "esbuild";
import { compile, compileModule } from "svelte/compiler";

// Vitest runs a non-bundled vite environment whose import analysis tries to
// parse every source file as JS. Vite's rollup build skips this (that's why
// `vite build` works with plain `.svelte` imports), so compile `.svelte`
// components and `.svelte.ts` rune modules to JS at load time for tests.
// `.svelte.ts` files are first type-stripped with esbuild (like
// vite-plugin-svelte's preprocess step), then compiled with svelte's module
// compiler so runes (`$state`, `$derived`, ...) stay valid.
function svelteLoadPlugin() {
  return {
    name: "vitest:svelte-load",
    enforce: "pre",
    async load(id: string) {
      const cleanId = id.split("?", 1)[0];
      if (!cleanId.match(/\.svelte(\.ts)?$/)) return null;
      const source = fs.readFileSync(cleanId, "utf-8");
      let js = source;
      if (id.endsWith(".ts")) {
        js = (await esbuild.transform(js, { loader: "ts", format: "esm", target: "es2023" })).code;
      }
      const compiled = id.endsWith(".ts")
        ? compileModule(js, { generate: "client", filename: id })
        : compile(js, { generate: "client", filename: id });
      return compiled.js.code;
    },
  };
}

export default defineConfig({
  resolve: {
    // The jsdom environment runs without the "browser" condition, so bare
    // "svelte" imports would resolve to the server build (no `mount`). Add it
    // back so tests can mount components with the client build.
    conditions: ["browser"],
    alias: {
      $app: fileURLToPath(new URL("./src/app", import.meta.url)),
      $shared: fileURLToPath(new URL("./src/shared", import.meta.url)),
      $entities: fileURLToPath(new URL("./src/entities", import.meta.url)),
      $features: fileURLToPath(new URL("./src/features", import.meta.url)),
      $widgets: fileURLToPath(new URL("./src/widgets", import.meta.url)),
      $views: fileURLToPath(new URL("./src/views", import.meta.url)),
    },
  },
  plugins: [svelteLoadPlugin()],
  test: {
    include: ["src/**/*.test.ts"],
    environment: "jsdom",
    // lucide-svelte re-exports `.svelte` icon sources from its `.js` barrel;
    // vitest externalises packages with `exports` maps by default, so force
    // inlining so the svelte load hook can compile them.
    server: {
      deps: { inline: ["lucide-svelte"] },
    },
    coverage: {
      provider: "v8",
      reporter: ["json-summary", "cobertura", "text"],
      reportsDirectory: "../reports/coverage/frontend",
      include: ["src/**/*.ts"],
      exclude: ["src/**/*.d.ts", "src/**/*.test.ts"],
    },
  },
});
