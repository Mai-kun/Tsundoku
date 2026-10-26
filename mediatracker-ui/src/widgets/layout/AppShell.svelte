<script lang="ts">
  import type { Snippet } from "svelte";
  import ToastContainer from "./ToastContainer.svelte";

  interface Props {
    sidebar: Snippet;
    header: Snippet;
    children: Snippet;
    mainRef?: (el: HTMLElement | null) => void;
  }

  let { sidebar, header, children, mainRef }: Props = $props();

  let mainElement = $state<HTMLElement | null>(null);

  $effect(() => {
    if (mainRef) mainRef(mainElement);
  });
</script>

<div class="bg-canvas text-ink flex h-dvh w-full overflow-hidden lg:pl-60">
  <aside
    data-widget="sidebar"
    class="bg-surface fixed inset-x-0 bottom-0 z-20 border-t border-white/[0.07] px-2 py-2 lg:inset-y-0 lg:right-auto lg:left-0 lg:w-60 lg:border-t-0 lg:border-r lg:px-3 lg:py-5"
  >
    {@render sidebar()}
  </aside>

  <div class="flex min-w-0 flex-1 flex-col lg:pl-0">
    <header
      data-widget="header"
      class="bg-surface z-20 flex h-14 shrink-0 items-center border-b border-white/[0.07]"
    >
      {@render header()}
    </header>

    <main
      id="main-scroll"
      bind:this={mainElement}
      class="min-h-0 flex-1 overflow-x-hidden overflow-y-auto px-4 pt-6 pb-24 sm:px-6 lg:px-8 lg:pb-8"
    >
      {@render children()}
    </main>
  </div>

  <ToastContainer />
</div>
