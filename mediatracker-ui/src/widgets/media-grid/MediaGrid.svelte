<script lang="ts">
    import { Inbox, RefreshCw, X } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaItem } from "$shared/types";
    import MediaCard from "$widgets/media-card/MediaCard.svelte";

    interface Props {
        items: MediaItem[];
        loading?: boolean;
        error?: unknown;
        onRetry?: () => void;
        onOpen?: (item: MediaItem) => void;
        onProgress?: (id: string, currentProgress: number) => Promise<void>;
        onProgressCommitted?: () => void;
        onStatusChange?: (
            item: MediaItem,
            newStatus: import("$shared/types").MediaStatus,
        ) => void;
        onDelete?: (item: MediaItem) => Promise<void>;
        onEdit?: (item: MediaItem) => void;
        onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
        onRemoveFromList?: (item: MediaItem) => Promise<void>;
    }

    let {
        items,
        loading = false,
        error = null,
        onRetry = () => {},
        onOpen = () => {},
        onProgress,
        onProgressCommitted = () => {},
        onStatusChange,
        onDelete,
        onEdit = () => {},
        onEpisodeStep,
        onRemoveFromList,
    }: Props = $props();
</script>

{#if loading}
    <div
        class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-7"
        aria-hidden="true"
    >
        {#each Array(7) as _, index (index)}
            <div class="overflow-hidden rounded-lg bg-card">
                <div class="aspect-[3/4] animate-pulse bg-card-hover"></div>
                <div class="space-y-2 p-3.5">
                    <div
                        class="h-4 w-3/4 animate-pulse rounded bg-canvas"
                    ></div>
                    <div
                        class="h-3 w-1/2 animate-pulse rounded bg-canvas"
                    ></div>
                </div>
            </div>
        {/each}
    </div>
    <p class="sr-only" role="status">{i18n.t.common.loading}</p>
{:else if error}
    <div
        class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
    >
        <p class="text-sm text-rose-200" role="alert">{errorMessage(error)}</p>
        <button
            type="button"
            class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover"
            onclick={onRetry}
            ><RefreshCw size={15} aria-hidden="true" />{i18n.t.common
                .retry}</button
        >
    </div>
{:else if items.length === 0}
    <div
        class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-surface p-6 text-center"
    >
        <div
            class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted"
        >
            <Inbox size={22} aria-hidden="true" />
        </div>
        <div>
            <p class="font-semibold text-ink">{i18n.t.library.emptyTitle}</p>
            <p class="mt-1 max-w-sm text-sm text-muted">
                {i18n.t.library.emptyHint}
            </p>
        </div>
    </div>
{:else}
    <div
        class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-7"
    >
        {#each items as item (item.id)}
            <div class="group relative min-w-0">
                <MediaCard
                    {item}
                    {onOpen}
                    {onProgress}
                    {onProgressCommitted}
                    {onStatusChange}
                    {onDelete}
                    {onEdit}
                    {onEpisodeStep}
                />
                {#if onRemoveFromList}
                    <button type="button" class="absolute right-2 top-2 z-10 grid h-8 w-8 place-items-center rounded-lg border border-white/10 bg-black/75 text-white opacity-100 transition hover:bg-rose-500 sm:opacity-0 sm:group-hover:opacity-100" title={i18n.t.views.listRemoveItem} aria-label={i18n.t.views.listRemoveItem} onclick={(event) => { event.stopPropagation(); void onRemoveFromList?.(item); }}>
                        <X size={15} aria-hidden="true" />
                    </button>
                {/if}
            </div>
        {/each}
    </div>
{/if}
