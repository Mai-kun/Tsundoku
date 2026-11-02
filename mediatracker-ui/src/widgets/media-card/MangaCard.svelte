<script lang="ts">
  import type { MangaMedia } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import BaseCard from "./BaseCard.svelte";
  import CardProgressBar from "./CardProgressBar.svelte";
  import CardProgressControls from "./CardProgressControls.svelte";
  import CardTitleBlock from "./CardTitleBlock.svelte";
  import { createCardProgress } from "$features/update-progress/progressController.svelte";
  import type { MediaCardProps } from "./cardTypes";

  let {
    item,
    timeHint,
    showProgress = true,
    onOpen = () => {},
    onProgress,
    onProgressCommitted = () => {},
    onStatusChange,
    onDelete,
    onEdit,
  }: MediaCardProps & { item: MangaMedia } = $props();

  const progress = createCardProgress({
    getItem: () => item,
    getOnProgress: () => onProgress,
    getOnProgressCommitted: () => onProgressCommitted,
    getOnStatusChange: () => onStatusChange,
  });
  // Same canonical `totalChapters` the detail screen reads, so the card and "Характеристики"
  // can never disagree. An unknown total renders as a dash rather than a misleading 0.
  const totalChapters = $derived(
    item.totalChapters && item.totalChapters > 0 ? item.totalChapters : null,
  );
  const ratio = $derived(totalChapters !== null ? progress.value / totalChapters : null);
  const subtitle = $derived(
    item.author?.trim() ? item.author : item.mangaFormat?.trim() || i18n.t.types.manga,
  );
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete} {onEdit}>
  <CardTitleBlock title={item.title} {subtitle} />

  {#if showProgress}
    <CardProgressBar label={i18n.t.card.chapters(progress.value, totalChapters)} {ratio} />
  {/if}

  {#snippet hover()}
    {#if showProgress}
      <CardProgressControls
        text={i18n.t.card.chapters(progress.value, totalChapters)}
        onStep={(delta) => progress.step(delta)}
        decrementDisabled={progress.value <= 0}
        error={progress.error}
      />
    {/if}
  {/snippet}
</BaseCard>
