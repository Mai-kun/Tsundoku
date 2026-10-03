<script lang="ts">
    import type { MangaMedia } from "$shared/types";
    import { i18n } from "$shared/i18n/index.svelte";
    import BaseCard from "./BaseCard.svelte";
    import CardProgressBar from "./CardProgressBar.svelte";
    import CardProgressControls from "./CardProgressControls.svelte";
    import CardTitleBlock from "./CardTitleBlock.svelte";
    import { createCardProgress } from "$features/update-progress/progressController.svelte";
    import { supportsProgressStepper } from "$entities/media/model/progressRules";
    import type { MediaCardProps } from "./cardTypes";

    let {
        item,
        onOpen = () => {},
        onProgress,
        onProgressCommitted = () => {},
        onStatusChange,
        onDelete,
    }: MediaCardProps & { item: MangaMedia } = $props();

    const progress = createCardProgress({
        getItem: () => item,
        getOnProgress: () => onProgress,
        getOnProgressCommitted: () => onProgressCommitted,
    });
    const showStepper = $derived(supportsProgressStepper(item));
    // Same canonical `totalChapters` the detail screen reads, so the card and "Характеристики"
    // can never disagree. An unknown total renders as a dash rather than a misleading 0.
    const totalChapters = $derived(
        item.totalChapters && item.totalChapters > 0 ? item.totalChapters : null,
    );
    const ratio = $derived(
        totalChapters !== null ? progress.value / totalChapters : null,
    );
    const subtitle = $derived(
        item.author?.trim()
            ? item.author
            : item.mangaFormat?.trim() || i18n.t.types.manga,
    );
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
        label={i18n.t.card.chapters(progress.value, totalChapters)}
        {ratio}
        reserveSpace={showStepper}
    />

    {#if showStepper}
        <CardProgressControls {progress} />
    {/if}
</BaseCard>