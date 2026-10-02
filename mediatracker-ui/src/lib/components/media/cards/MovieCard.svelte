<script lang="ts">
    import type { MovieMedia } from "$lib/types";
    import { i18n } from "$lib/i18n/index.svelte";
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
    }: MediaCardProps & { item: MovieMedia } = $props();
</script>

<BaseCardContainer
    {item}
    {onOpen}
    {onStatusChange}
    {onProgressCommitted}
    {onDelete}
>
    <CardTitleBlock
        title={item.title}
        subtitle={item.director?.trim() || i18n.t.types.movie}
    />

    <CardProgressBar
        label={i18n.t.card.movie(item.durationMinutes)}
        ratio={null}
    />
</BaseCardContainer>