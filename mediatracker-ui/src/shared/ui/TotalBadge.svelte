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

<!-- Plain counter for toolbars: no pill, no border, no background. -->
<span class="text-xs text-white/50 tabular-nums select-none">
  {#if shown < total}
    {i18n.t.library.resultCountWithShown(total, shown)}
  {:else}
    {i18n.t.library.resultCount(total)}
  {/if}
</span>
