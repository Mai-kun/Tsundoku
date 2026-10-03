<script lang="ts">
    import type {
        RelatedEntry,
        RelatedViewMode,
        RelationGroup,
        TimelineEntry,
    } from "../detailTypes";
    import RelatedPanel from "../panels/RelatedPanel.svelte";

    interface Props {
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
    }

    let {
        related,
        loading,
        error,
        viewMode,
        groups,
        timeline,
        onRetry,
        onSelectViewMode,
        onOpen,
    }: Props = $props();
</script>

<RelatedPanel
    {related}
    {loading}
    {error}
    {viewMode}
    {groups}
    {timeline}
    {onRetry}
    {onSelectViewMode}
    {onOpen}
/>
