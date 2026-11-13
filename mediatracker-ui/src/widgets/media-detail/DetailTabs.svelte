<script lang="ts">
  import { Sparkles } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { SubTab } from "./detailTypes";

  interface Props {
    active: SubTab;
    mediaType: string;
    /** Undefined for non-shows; drives the "3/12" badge on the episodes tab. */
    seasonProgress: { current: number; total: number | null } | null;
    relatedCount?: number;
    /** User screenshots stored on the row; drives the badge on the gallery tab. */
    galleryCount?: number;
    onSelect: (tab: SubTab) => void;
  }

  let {
    active,
    mediaType,
    seasonProgress,
    relatedCount = 0,
    galleryCount = 0,
    onSelect,
  }: Props = $props();

  function tabClass(tab: SubTab): string {
    return `flex items-center gap-2 whitespace-nowrap px-3 py-2.5 text-sm font-semibold transition sm:px-4 ${
      active === tab ? "text-white" : "text-muted hover:text-white"
    }`;
  }

  // The underline is a single physical element that slides between buttons
  // instead of a per-button border that pops out and in.
  let navElement: HTMLElement | null = $state(null);
  let indicatorStyle = $state("opacity: 0;");

  function positionIndicator() {
    const nav = navElement;
    if (!nav) return;
    const button = nav.querySelector<HTMLElement>(`[data-tab="${active}"]`);
    if (!button) {
      indicatorStyle = "opacity: 0;";
      return;
    }
    indicatorStyle = `transform: translateX(${button.offsetLeft}px); width: ${button.offsetWidth}px; opacity: 1;`;
  }

  $effect(() => {
    void active;
    positionIndicator();
  });

  // Horizontal scrolling and late font swaps change the buttons' boxes: keep the
  // indicator glued to the active tab.
  $effect(() => {
    const nav = navElement;
    if (!nav) return;
    positionIndicator();
    const observer = new ResizeObserver(() => positionIndicator());
    observer.observe(nav);
    window.addEventListener("resize", positionIndicator);
    if (typeof document !== "undefined" && "fonts" in document) {
      void document.fonts.ready.then(() => positionIndicator());
    }
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", positionIndicator);
    };
  });
</script>

<!-- Horizontal scroll on narrow screens: the nowrap tabs (four on games, five on shows) no
     longer fit a 320-390px viewport, and wrapping would break the active underline. -->
<nav
  bind:this={navElement}
  class="thin-scroll relative flex items-center gap-1 overflow-x-auto border-b border-white/[0.08] pb-px"
  aria-label="Sections"
>
  <button type="button" data-tab="overview" class={tabClass("overview")} onclick={() => onSelect("overview")}>
    {i18n.t.detail.tabOverview}
  </button>

  {#if mediaType === "tvshow"}
    <button type="button" data-tab="episodes" class={tabClass("episodes")} onclick={() => onSelect("episodes")}>
      {i18n.t.detail.tabEpisodes}
      {#if seasonProgress}
        <span class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-[var(--color-accent-soft)]">
          {seasonProgress.current}/{seasonProgress.total}
        </span>
      {/if}
    </button>
  {/if}

  <!-- The gallery tab is type-agnostic: every title can carry user screenshots. -->
  <button type="button" data-tab="gallery" class={tabClass("gallery")} onclick={() => onSelect("gallery")}>
    {i18n.t.detail.tabGallery}
    {#if galleryCount > 0}
      <span class="text-muted rounded-full bg-white/10 px-2 py-0.5 text-xs">
        {galleryCount}
      </span>
    {/if}
  </button>

  <button type="button" data-tab="related" class={tabClass("related")} onclick={() => onSelect("related")}>
    {i18n.t.detail.tabRelatedMedia}
    {#if relatedCount > 0}
      <span class="text-muted rounded-full bg-white/10 px-2 py-0.5 text-xs">
        {relatedCount}
      </span>
    {/if}
  </button>

  <button
    type="button"
    data-tab="recommendations"
    class={tabClass("recommendations")}
    onclick={() => {
      // No fetch here: the tab renders the recommendations already stored on the row.
      onSelect("recommendations");
    }}
  >
    <Sparkles size={14} class="text-[var(--color-accent-soft)]" aria-hidden="true" />
    {i18n.t.detail.tabRecommendations}
  </button>

  <span
    aria-hidden="true"
    class="pointer-events-none absolute bottom-0 left-0 h-0.5 rounded-full bg-[var(--color-accent)] transition-[transform,width] duration-200 ease-[cubic-bezier(0.2,0,0,1)]"
    style={indicatorStyle}
  ></span>
</nav>
