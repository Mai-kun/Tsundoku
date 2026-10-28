<script lang="ts">
  import type { Snippet } from "svelte";
  import Placeholder404 from "./Placeholder404.svelte";
  import { AlertTriangle, LoaderCircle } from "$shared/ui/Icons.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { jobsClient } from "$shared/api/jobsClient.svelte";

  interface Props {
    src: string | null;
    alt: string;
    /** Status + score cluster, rendered inside the poster's top-left corner. */
    badges?: Snippet;
    /** Destructive/secondary actions, rendered top-right and revealed on hover. */
    actions?: Snippet;
    /** Background enrichment is still filling this item in. The card stays clickable. */
    syncing?: boolean;
    /** The matcher parked this title for manual confirmation; the badge opens the review tab. */
    needsReview?: boolean;
  }

  let { src, alt, badges, actions, syncing = false, needsReview = false }: Props = $props();

  /** A broken remote/проксирующий link is a "cover not found" case, not a retry loop forever. */
  let imgError = $state(false);
  $effect(() => {
    // Reset on a new src: another sync may have repaired the cover.
    void src;
    imgError = false;
  });
</script>

<div class="bg-canvas relative aspect-[3/4] overflow-hidden rounded-lg">
  {#if src && src.startsWith("/") && !imgError}
    <img
      {src}
      {alt}
      referrerpolicy="no-referrer"
      class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
      loading="lazy"
      decoding="async"
      fetchpriority="low"
      onerror={() => {
        imgError = true;
      }}
    />
  {:else}
    <Placeholder404 />
  {/if}

  {#if syncing}
    <div class="absolute inset-0 z-[5] flex flex-col items-center justify-center gap-2 bg-black/80">
      <LoaderCircle size={22} class="animate-spin text-white/90" aria-hidden="true" />
      <span
        class="rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold tracking-wide text-white/90"
      >
        {i18n.t.activity.syncing}
      </span>
    </div>
  {/if}

  {#if needsReview}
    <button
      type="button"
      class="absolute inset-x-2.5 bottom-2.5 z-20 inline-flex cursor-pointer items-center justify-center gap-1 rounded-md bg-amber-500/90 px-2.5 py-1 text-[11px] font-bold text-black shadow-lg transition hover:bg-amber-400"
      onclick={(event) => {
        event.stopPropagation();
        jobsClient.openModal("review");
      }}
    >
      <AlertTriangle size={16} aria-hidden="true" />
      {i18n.t.backgroundJobs.refineBadge}
    </button>
  {/if}

  <div class="absolute inset-x-0 top-0 z-10 flex items-start justify-between gap-2 p-2.5">
    <div class="relative flex items-center">
      {@render badges?.()}
    </div>
    {#if actions}
      <div class="flex items-center gap-1.5">
        {@render actions()}
      </div>
    {/if}
  </div>
</div>
