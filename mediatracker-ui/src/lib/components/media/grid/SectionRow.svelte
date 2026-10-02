<script lang="ts">
    import type { MediaItem, MediaStatus } from "$lib/types";
    import MediaGrid from "./MediaGrid.svelte";

    interface Props {
        title: string;
        items: MediaItem[];
        onRetry?: () => void;
        onOpen?: (item: MediaItem) => void;
        onProgress?: (id: string, currentProgress: number) => Promise<void>;
        onProgressCommitted?: () => void;
        onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
        onDelete?: (item: MediaItem) => Promise<void>;
        onEdit?: (item: MediaItem) => void;
        onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
    }

    let {
        title,
        items,
        onRetry = () => {},
        onOpen = () => {},
        onProgress,
        onProgressCommitted = () => {},
        onStatusChange,
        onDelete,
        onEdit = () => {},
        onEpisodeStep,
    }: Props = $props();
</script>

<section class="space-y-3">
    <div class="flex items-center gap-2">
        <h2 class="text-[25px] font-bold tracking-wide text-white">
            {title}
        </h2>
        <span
            class="rounded-full bg-surface px-2.5 py-0.5 text-xs font-semibold text-muted"
            >{items.length}</span
        >
    </div>
    <MediaGrid
        {items}
        loading={false}
        error={null}
        {onRetry}
        {onOpen}
        {onProgress}
        {onProgressCommitted}
        {onStatusChange}
        {onDelete}
        {onEdit}
        {onEpisodeStep}
    />
</section>