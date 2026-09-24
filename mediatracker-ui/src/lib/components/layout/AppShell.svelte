<script lang="ts">
  import type { Snippet } from 'svelte'

  interface Props {
    sidebar: Snippet
    header: Snippet
    children: Snippet
  }

  let { sidebar, header, children }: Props = $props()
</script>

<div class="min-h-screen bg-canvas text-ink lg:pl-60">
  <aside class="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-surface/95 px-2 py-2 backdrop-blur lg:inset-y-0 lg:left-0 lg:right-auto lg:w-60 lg:border-r lg:border-t-0 lg:px-3 lg:py-5">
    {@render sidebar()}
  </aside>

  <header class="sticky top-0 z-20 h-14 border-b border-border bg-canvas/90 backdrop-blur">
    {@render header()}
  </header>

  <main class="min-h-[calc(100vh-3.5rem)] overflow-x-hidden px-4 pb-24 pt-6 sm:px-6 lg:h-[calc(100vh-3.5rem)] lg:overflow-y-auto lg:px-8 lg:pb-8">
    {@render children()}
  </main>
</div>
