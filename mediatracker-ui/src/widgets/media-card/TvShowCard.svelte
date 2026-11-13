<script lang="ts">
  import type { MediaStatus, TvShowMedia } from "$shared/types";
  import { untrack } from "svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import MediaStatusBadge from "$entities/media/ui/MediaStatusBadge.svelte";
  import { reconcileProgress } from "$features/update-progress/optimisticProgress.svelte";
  import { stepSeriesEpisodes } from "$features/update-progress/seriesProgressController.svelte";
  import { cardTypeLabel } from "$entities/media/model/mediaLabels";
  import BaseCard from "./BaseCard.svelte";
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
    onEdit,
    onEpisodeStep,
  }: MediaCardProps & { item: TvShowMedia } = $props();

  // Optimistic counter: the real commit runs a detail fetch + season POST + refetch and can
  // take seconds, so the card renders from a local copy that steps instantly on click and
  // resyncs from props whenever the view sends refreshed data. reconcileProgress holds a
  // pending step (this card's or the detail page's) against stale refetched data.
  let localEpisodesWatched = $state(untrack(() => item.totalEpisodesWatched ?? 0));

  $effect(() => {
    localEpisodesWatched = reconcileProgress(item.id, item.totalEpisodesWatched ?? 0);
  });

  // The card and the detail screen read the same counters; the guard only covers a show whose
  // seasons have not been written yet, so a known episode count is still shown instead of "0".
  const totalEpisodes = $derived(item.totalEpisodesCount > 0 ? item.totalEpisodesCount : null);

  const subtitle = $derived(
    item.seasonsCount > 0 ? `${cardTypeLabel(item)} • ${item.seasonsCount}` : cardTypeLabel(item),
  );

  /* A single-episode title still needs the stepper: 0/1 -> 1/1 is a valid step. */
  const showStepper = $derived(Boolean(onEpisodeStep));

  const episodeText = $derived(
    totalEpisodes !== null
      ? `${localEpisodesWatched} / ${totalEpisodes}`
      : String(localEpisodesWatched),
  );

  const atLastEpisode = $derived(totalEpisodes !== null && localEpisodesWatched >= totalEpisodes);

  async function stepEpisode(delta: number) {
    if (!onEpisodeStep) return;
    // Instant local counter; the controller owns the raw item write, the
    // shared optimistic store, the detail-cache patch and the debounced PUT.
    localEpisodesWatched = Math.max(0, localEpisodesWatched + delta);
    stepSeriesEpisodes(item, delta, { onCommitted: () => onProgressCommitted() });
    // Absolute value, not a delta: the controller has already applied the step
    // to item, so a parent that added delta again would double-count the click.
    await onEpisodeStep(item, localEpisodesWatched);
  }

  function statusProxy(next: MediaStatus) {
    void onStatusChange?.(item, next);
  }

  /** Hover stepper: the series controller owns the status rule (0 → 1 ⇒ InProgress). */
  function stepFromHover(delta: number) {
    void stepEpisode(delta);
  }
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete} {onEdit}>
  <CardTitleBlock title={item.title} {subtitle} />

  {#snippet hover()}
    {#if showStepper && onEpisodeStep}
      <CardProgressControls
        text={episodeText}
        onStep={stepFromHover}
        decrementDisabled={localEpisodesWatched <= 0}
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
