import { svelte } from '@sveltejs/vite-plugin-svelte'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte(), tailwindcss()],
  build: {
    outDir: '../MediaTracker.Server/wwwroot',
  },
  server: {
    proxy: {
      '/api': 'http://localhost:5000',
    },
  },
})
