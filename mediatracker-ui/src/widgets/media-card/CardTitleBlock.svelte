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
  <h2
    class="line-clamp-2 text-sm leading-tight font-semibold text-white drop-shadow-sm"
    title={titleTooltip(title)}
  >
    {title}
  </h2>
  <p class="mt-0.5 line-clamp-1 text-xs text-white/60">{subtitle}</p>
</div>
