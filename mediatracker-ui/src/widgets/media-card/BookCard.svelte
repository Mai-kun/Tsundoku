<script lang="ts">
  import type { BookMedia } from "$shared/types";
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
  }: MediaCardProps & { item: BookMedia } = $props();

  const progress = createCardProgress({
    getItem: () => item,
    getOnProgress: () => onProgress,
    getOnProgressCommitted: () => onProgressCommitted,
    getOnStatusChange: () => onStatusChange,
  });
  const ratio = $derived(item.totalPages > 0 ? progress.value / item.totalPages : null);
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete}>
  {#snippet children()}
    <CardTitleBlock title={item.title} subtitle={item.author || i18n.t.types.book} />

    {#if showProgress}
      <CardProgressBar label={i18n.t.card.pages(progress.value, item.totalPages)} {ratio} />
    {/if}
  {/snippet}

  {#snippet hover()}
    {#if showProgress}
      <CardProgressControls
        text={i18n.t.card.pages(progress.value, item.totalPages)}
        onStep={(delta) => progress.step(delta)}
        decrementDisabled={progress.value <= 0}
        error={progress.error}
      />
    {/if}
  {/snippet}
</BaseCard>
