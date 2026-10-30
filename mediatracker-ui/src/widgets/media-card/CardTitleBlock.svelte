<script lang="ts">
  import { titleTooltip } from "$entities/media/model/mediaLabels";

  interface Props {
    title: string;
    /** Platform, author, media type — the single muted line under the title. */
    subtitle: string;
    /** Optional click handler for backwards compatibility. */
    onOpen?: () => void;
  }

  let { title, subtitle }: Props = $props();
</script>

<div class="min-w-0">
  <h2 class="text-ink truncate text-sm font-semibold break-words" title={titleTooltip(title)}>
    {title}
  </h2>
  <p class="text-muted mt-1 hidden truncate text-xs sm:block">{subtitle}</p>
</div>
