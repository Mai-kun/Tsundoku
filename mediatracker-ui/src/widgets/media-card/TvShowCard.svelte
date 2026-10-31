<script lang="ts">
  import type { MediaStatus, TvShowMedia } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import MediaStatusBadge from "$entities/media/ui/MediaStatusBadge.svelte";
  import { transitionToInProgress } from "$features/update-progress/progressController.svelte";
  import { cardTypeLabel } from "$entities/media/model/mediaLabels";
  import BaseCard from "./BaseCard.svelte";
  import CardProgressBar from "./CardProgressBar.svelte";
  import CardProgressControls from "./CardProgressControls.svelte";
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
    onEpisodeStep,
  }: MediaCardProps & { item: TvShowMedia } = $props();

  // The card and the detail screen read the same counters; the guard only covers a show whose
  // seasons have not been written yet, so a known episode count is still shown instead of "0".
  const totalEpisodes = $derived(item.totalEpisodesCount > 0 ? item.totalEpisodesCount : null);

  const ratio = $derived(totalEpisodes !== null ? item.totalEpisodesWatched / totalEpisodes : null);

  const subtitle = $derived(
    item.seasonsCount > 0 ? `${cardTypeLabel(item)} • ${item.seasonsCount}` : cardTypeLabel(item),
  );

  /* A single-episode "show" has nothing to step through. */
  const showStepper = $derived(Boolean(onEpisodeStep) && totalEpisodes !== 1);

  const episodeText = $derived(
    totalEpisodes !== null
      ? `${item.totalEpisodesWatched} / ${totalEpisodes}`
      : String(item.totalEpisodesWatched),
  );

  const atLastEpisode = $derived(
    totalEpisodes !== null && item.totalEpisodesWatched >= totalEpisodes,
  );

  async function stepEpisode(delta: number) {
    if (!onEpisodeStep) return;
    await onEpisodeStep(item, delta);
  }

  function statusProxy(next: MediaStatus) {
    void onStatusChange?.(item, next);
  }

  /** Hover stepper: stepping a non-InProgress show means watching resumed. */
  function stepFromHover(delta: number) {
    transitionToInProgress(item, onStatusChange);
    void stepEpisode(delta);
  }
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete}>
  <CardTitleBlock title={item.title} {subtitle} />

  {#if showProgress}
    <CardProgressBar
      label={i18n.t.card.episodes(item.totalEpisodesWatched, totalEpisodes ?? 0)}
      {ratio}
    />
  {/if}

  {#snippet hover()}
    {#if showStepper && onEpisodeStep}
      <CardProgressControls
        text={episodeText}
        onStep={stepFromHover}
        decrementDisabled={item.totalEpisodesWatched <= 0}
        incrementDisabled={atLastEpisode}
      />
    {:else}
      <MediaStatusBadge
        id={`status-hover-${item.id}`}
        status={item.status}
        onSelect={(next) => void statusProxy(next)}
      />
    {/if}
  {/snippet}
</BaseCard>
