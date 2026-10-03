<script lang="ts">
    import { MEDIA_STATUS, type TvShowMedia } from "$shared/types";
    import { i18n } from "$shared/i18n/index.svelte";
    import MediaStepper from "$entities/media/ui/MediaStepper.svelte";
    import { cardTypeLabel } from "$entities/media/model/mediaLabels";
    import BaseCard from "./BaseCard.svelte";
    import CardProgressBar from "./CardProgressBar.svelte";
    import CardTitleBlock from "./CardTitleBlock.svelte";
    import type { MediaCardProps } from "./cardTypes";

    let {
        item,
        onOpen = () => {},
        onStatusChange,
        onProgressCommitted = () => {},
        onDelete,
        onEpisodeStep,
    }: MediaCardProps & { item: TvShowMedia } = $props();

    // The card and the detail screen read the same counters; the guard only covers a show whose
    // seasons have not been written yet, so a known episode count is still shown instead of "0".
    const totalEpisodes = $derived(
        item.totalEpisodesCount > 0 ? item.totalEpisodesCount : null,
    );

    const ratio = $derived(
        totalEpisodes !== null ? item.totalEpisodesWatched / totalEpisodes : null,
    );

    const subtitle = $derived(
        item.seasonsCount > 0
            ? `${cardTypeLabel(item)} • ${item.seasonsCount}`
            : cardTypeLabel(item),
    );

    /* A single-episode "show" has nothing to step through. */
    const showStepper = $derived(
        Boolean(onEpisodeStep) &&
            item.status === MEDIA_STATUS.inProgress &&
            totalEpisodes !== 1,
    );

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
</script>

<BaseCard
    {item}
    {onOpen}
    {onStatusChange}
    {onProgressCommitted}
    {onDelete}
>
    <CardTitleBlock title={item.title} {subtitle} />

    <CardProgressBar
        label={i18n.t.card.episodes(
            item.totalEpisodesWatched,
            totalEpisodes ?? 0,
        )}
        {ratio}
    />

    {#if showStepper && onEpisodeStep}
        <MediaStepper
            text={episodeText}
            onStep={(delta) => void stepEpisode(delta)}
            decrementDisabled={item.totalEpisodesWatched <= 0}
            incrementDisabled={atLastEpisode}
        />
    {/if}
</BaseCard>