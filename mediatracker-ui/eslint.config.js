import js from "@eslint/js";
import ts from "typescript-eslint";
import svelte from "eslint-plugin-svelte";
import svelteParser from "svelte-eslint-parser";
import globals from "globals";

export default ts.config(
  js.configs.recommended,
  ...ts.configs.recommended,
  ...svelte.configs["flat/recommended"],
  {
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node,
      },
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
      },
    },
  },
  {
    files: ["**/*.ts", "**/*.svelte.ts"],
    languageOptions: {
      parser: ts.parser,
    },
    rules: {
      "@typescript-eslint/no-unused-vars": "off",
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-unused-expressions": "off",
      "no-empty": "off",
      "no-useless-escape": "off",
      "no-useless-assignment": "off",
      "prefer-const": "off",
    },
  },
  {
    files: ["**/*.svelte"],
    languageOptions: {
      parser: svelteParser,
      parserOptions: {
        parser: ts.parser,
        extraFileExtensions: [".svelte"],
      },
    },
    rules: {
      // Real bugs: interactive nesting, each keys, runes correctness
      "svelte/valid-each-key": "error",
      "svelte/no-at-html-tags": "off",
      "svelte/prefer-svelte-reactivity": "off",
      "svelte/prefer-writable-derived": "off",
      "svelte/no-unused-svelte-ignore": "off",
      "svelte/no-inspect": "off",
      "svelte/require-each-key": "off",
      "@typescript-eslint/no-unused-vars": "off",
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-unused-expressions": "off",
      "no-empty": "off",
      "no-useless-escape": "off",
      "no-useless-assignment": "off",
      "no-undef": "off",
      "prefer-const": "off",
    },
  },
  {
    ignores: [
      "node_modules/**",
      "dist/**",
      "../MediaTracker.Server/wwwroot/**",
      "../reports/**",
      "checks/*.cjs",
      "checks/*.check.ts",
    ],
  },
);
