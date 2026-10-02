<script lang="ts">
    import { MEDIA_STATUS, type TvShowMedia } from "$lib/types";
    import { i18n } from "$lib/i18n/index.svelte";
    import MediaProgressStepper from "../atoms/MediaProgressStepper.svelte";
    import { cardTypeLabel } from "../mediaLabels";
    import BaseCardContainer from "./BaseCardContainer.svelte";
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

    const ratio = $derived(
        item.totalEpisodesCount > 0
            ? item.totalEpisodesWatched / item.totalEpisodesCount
            : null,
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
            item.totalEpisodesCount !== 1,
    );

    const episodeText = $derived(
        item.totalEpisodesCount > 0
            ? `${item.totalEpisodesWatched} / ${item.totalEpisodesCount}`
            : String(item.totalEpisodesWatched),
    );

    const atLastEpisode = $derived(
        item.totalEpisodesCount > 0 &&
            item.totalEpisodesWatched >= item.totalEpisodesCount,
    );

    async function stepEpisode(delta: number) {
        if (!onEpisodeStep) return;
        await onEpisodeStep(item, delta);
    }
</script>

<BaseCardContainer
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
            item.totalEpisodesCount,
        )}
        {ratio}
    />

    {#if showStepper && onEpisodeStep}
        <MediaProgressStepper
            text={episodeText}
            onStep={(delta) => void stepEpisode(delta)}
            decrementDisabled={item.totalEpisodesWatched <= 0}
            incrementDisabled={atLastEpisode}
        />
    {/if}
</BaseCardContainer>