<script lang="ts">
    import type { GameMedia } from "$shared/types";
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
    }: MediaCardProps & { item: GameMedia } = $props();

    const progress = createCardProgress({
        getItem: () => item,
        getOnProgress: () => onProgress,
        getOnProgressCommitted: () => onProgressCommitted,
    });
    const showStepper = $derived(supportsProgressStepper(item));

    /** Games list every platform shipped on; only the user's pick is meaningful. */
    const platform = $derived(
        item.userPlatform?.trim() || item.platform?.trim() || null,
    );
</script>

<BaseCard
    {item}
    {onOpen}
    {onStatusChange}
    {onProgressCommitted}
    {onDelete}
>
    <CardTitleBlock
        title={item.title}
        subtitle={platform ?? i18n.t.types.game}
    />

    <CardProgressBar label={i18n.t.card.hours(progress.value)} ratio={null} />

    {#if showStepper}
        <CardProgressControls {progress} />
    {/if}
</BaseCard>