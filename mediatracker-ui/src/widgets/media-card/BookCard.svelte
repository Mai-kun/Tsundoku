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
    onEdit,
  }: MediaCardProps & { item: BookMedia } = $props();

  const progress = createCardProgress({
    getItem: () => item,
    getOnProgress: () => onProgress,
    getOnProgressCommitted: () => onProgressCommitted,
    getOnStatusChange: () => onStatusChange,
  });

  const isNovel = $derived(item.format === "light_novel" || item.format === "web_novel");
  const total = $derived(isNovel ? (item.totalChapters ?? 0) : item.totalPages);
  const ratio = $derived(total > 0 ? progress.value / total : null);
  const progressText = $derived(
    isNovel
      ? i18n.t.card.chapters(progress.value, item.totalChapters ?? null)
      : i18n.t.card.pages(progress.value, item.totalPages),
  );
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete} {onEdit}>
  <CardTitleBlock
    title={item.title}
    subtitle={item.author ||
      (isNovel
        ? item.format === "web_novel"
          ? i18n.t.detail.mangaFormats.web_novel
          : i18n.t.detail.mangaFormats.light_novel
        : i18n.t.types.book)}
  />

  {#if showProgress}
    <CardProgressBar label={progressText} {ratio} />
  {/if}

  {#snippet hover()}
    {#if showProgress}
      <CardProgressControls
        text={progressText}
        onStep={(delta) => progress.step(delta)}
        decrementDisabled={progress.value <= 0}
        error={progress.error}
      />
    {/if}
  {/snippet}
</BaseCard>
