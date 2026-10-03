<script lang="ts">
    import type { MediaItem } from "$shared/types";
import type { RelatedEntry, RelatedViewMode, RelationGroup, TimelineEntry } from "../detailTypes";
import RelatedPanel from "../panels/RelatedPanel.svelte";

    interface Props {
        media: MediaItem;
        related: readonly RelatedEntry[];
        loading: boolean;
        error: unknown;
        viewMode: RelatedViewMode;
        groups: readonly RelationGroup[];
        timeline: readonly TimelineEntry[];
        onRetry: () => void;
        onSelectViewMode: (mode: RelatedViewMode) => void;
        /** Opens a local item, or the preview modal for an external one. */
        onOpen: (entry: RelatedEntry) => void;
        onLoadFrom: (source: string, force?: boolean) => void;
    }

    let {
        media,
        related,
        loading,
        error,
        viewMode,
        groups,
        timeline,
        onRetry,
        onSelectViewMode,
        onOpen,
        onLoadFrom,
    }: Props = $props();
</script>

<RelatedPanel
    {media}
    {related}
    {loading}
    {error}
    {viewMode}
    {groups}
    {timeline}
    {onRetry}
    {onSelectViewMode}
    {onOpen}
    {onLoadFrom}
/>
