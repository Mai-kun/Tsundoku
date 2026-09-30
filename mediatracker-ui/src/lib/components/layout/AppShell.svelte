<script lang="ts">
  import ArrowUp from 'lucide-svelte/icons/arrow-up'
  import type { Snippet } from 'svelte'
  import ToastContainer from './ToastContainer.svelte'

  interface Props {
    sidebar: Snippet
    header: Snippet
    children: Snippet
    mainRef?: (el: HTMLElement | null) => void
  }

  let { sidebar, header, children, mainRef }: Props = $props()

  let mainElement = $state<HTMLElement | null>(null)
  let showScrollTop = $state(false)

  $effect(() => {
    if (mainRef) mainRef(mainElement)
  })

  function handleScroll() {
    const mainScroll = mainElement ? mainElement.scrollTop : 0
    const windowScroll = typeof window !== 'undefined' ? window.scrollY : 0
    showScrollTop = mainScroll > 300 || windowScroll > 300
  }

  function scrollToTop() {
    if (mainElement) {
      mainElement.scrollTo({ top: 0, behavior: 'smooth' })
    }
    if (typeof window !== 'undefined') {
      window.scrollTo({ top: 0, behavior: 'smooth' })
    }
  }
</script>

<svelte:window onscroll={handleScroll} />

<div class="min-h-screen bg-canvas text-ink lg:pl-60">
  <aside class="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-surface px-2 py-2 lg:inset-y-0 lg:left-0 lg:right-auto lg:w-60 lg:border-r lg:border-t-0 lg:px-3 lg:py-5">
    {@render sidebar()}
  </aside>

  <header class="sticky top-0 z-20 h-14 border-b border-border bg-surface">
    {@render header()}
  </header>

  <main
    bind:this={mainElement}
    onscroll={handleScroll}
    class="min-h-[calc(100vh-3.5rem)] overflow-x-hidden px-4 pb-24 pt-6 sm:px-6 lg:h-[calc(100vh-3.5rem)] lg:overflow-y-auto lg:px-8 lg:pb-8"
  >
    {@render children()}
  </main>

  {#if showScrollTop}
    <button
      type="button"
      class="fixed bottom-6 right-6 z-40 flex h-11 w-11 items-center justify-center rounded-full bg-accent text-white shadow-lg shadow-black/50 transition duration-200 hover:scale-110 hover:bg-accent-hover active:scale-95"
      aria-label="Scroll to top"
      onclick={scrollToTop}
    >
      <ArrowUp size={20} stroke-width={2.2} aria-hidden="true" />
    </button>
  {/if}

  <ToastContainer />
</div>

