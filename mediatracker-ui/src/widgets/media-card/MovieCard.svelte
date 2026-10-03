<script lang="ts">
    import type { MovieMedia } from "$shared/types";
    import { i18n } from "$shared/i18n/index.svelte";
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
    }: MediaCardProps & { item: MovieMedia } = $props();
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
        subtitle={item.director?.trim() || i18n.t.types.movie}
    />

    <CardProgressBar
        label={i18n.t.card.movie(item.durationMinutes)}
        ratio={null}
    />
</BaseCard>