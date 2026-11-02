<script lang="ts">
  import type { MovieMedia } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import MediaStatusBadge from "$entities/media/ui/MediaStatusBadge.svelte";
  import BaseCard from "./BaseCard.svelte";
  import CardProgressBar from "./CardProgressBar.svelte";
  import CardTitleBlock from "./CardTitleBlock.svelte";
  import type { MediaCardProps } from "./cardTypes";

  let {
    item,
    timeHint,
    showProgress = true,
    onOpen = () => {},
    onStatusChange,
    onProgressCommitted = () => {},
    onDelete,
    onEdit,
  }: MediaCardProps & { item: MovieMedia } = $props();
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete} {onEdit}>
  <CardTitleBlock title={item.title} subtitle={item.director?.trim() || i18n.t.types.movie} />

  {#if showProgress}
    <CardProgressBar label={i18n.t.card.movie(item.durationMinutes)} ratio={null} />
  {/if}

  {#snippet hover()}
    <MediaStatusBadge
      id={`status-hover-${item.id}`}
      status={item.status}
      onSelect={(next) => void onStatusChange?.(item, next)}
    />
  {/snippet}
</BaseCard>
