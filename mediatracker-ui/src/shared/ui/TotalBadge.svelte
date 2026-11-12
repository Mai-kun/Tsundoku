<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";

  interface Props {
    /** Filtered total the badge counts. */
    total: number;
    /** Items that actually reached the client; smaller than total explains the window. */
    shown?: number;
  }

  let { total, shown = total }: Props = $props();
</script>

<!-- Neutral "Всего: N" pill for toolbars: matte glass, readable on any surface. -->
<span
  class="inline-flex items-center rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-medium text-white/70 tabular-nums select-none"
>
  {#if shown < total}
    {i18n.t.library.resultCountWithShown(total, shown)}
  {:else}
    {i18n.t.library.resultCount(total)}
  {/if}
</span>
