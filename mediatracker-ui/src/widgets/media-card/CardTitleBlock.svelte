<script lang="ts">
  import { titleTooltip } from "$entities/media/model/mediaLabels";

  interface Props {
    title: string;
    /** Platform, author, media type — the single muted line under the title. */
    subtitle: string;
    onOpen?: () => void;
  }

  let { title, subtitle, onOpen }: Props = $props();
</script>

<div class="min-w-0">
  <h2 class="text-ink truncate text-sm font-semibold break-words" title={titleTooltip(title)}>
    {#if onOpen}
      <button
        type="button"
        class="text-ink max-w-full cursor-pointer truncate text-left font-semibold hover:underline focus:outline-none focus-visible:ring-1 focus-visible:ring-indigo-400"
        onclick={(e) => {
          e.stopPropagation();
          onOpen();
        }}
      >
        {title}
      </button>
    {:else}
      {title}
    {/if}
  </h2>
  <p class="text-muted mt-1 hidden truncate text-xs sm:block">{subtitle}</p>
</div>
