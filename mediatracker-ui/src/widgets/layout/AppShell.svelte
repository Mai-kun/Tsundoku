<script lang="ts">
  import type { Snippet } from "svelte";
  import ContextMenu from "$shared/ui/ContextMenu.svelte";
  import ImageLightbox from "$shared/ui/ImageLightbox.svelte";
  import ListPicker from "$features/lists/ListPicker.svelte";
  import { activeListPickerMediaId, closeListPicker } from "$shared/ui/contextMenu.svelte";
  import { closeLightbox, lightboxUrl } from "$shared/ui/lightbox.svelte";
  import ToastContainer from "./ToastContainer.svelte";

  interface Props {
    sidebar: Snippet;
    header: Snippet;
    children: Snippet;
    mainRef?: (el: HTMLElement | null) => void;
    noPadding?: boolean;
  }

  let { sidebar, header, children, mainRef, noPadding = false }: Props = $props();

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
      class="min-h-0 flex-1 overflow-x-hidden {noPadding ? 'h-full overflow-hidden p-0' : 'overflow-y-auto p-6'}"
    >
      {@render children()}
    </main>
  </div>

  {#if $activeListPickerMediaId}
    <ListPicker mediaId={$activeListPickerMediaId} isOpen={true} onClose={closeListPicker} />
  {/if}

  <ContextMenu />

  <!-- Top-level on purpose: outside the `.view-fade` transform containers, so the fixed
       overlay centers on the monitor rather than the content column. -->
  <ImageLightbox url={$lightboxUrl} onclose={closeLightbox} />

  <ToastContainer />
</div>
