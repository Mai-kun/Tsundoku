<script lang="ts">
    import type { Snippet } from "svelte";
    import { Trash2 } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaItem, MediaStatus } from "$shared/types";
    import { schedulePrefetchMediaDetail } from "$features/prefetch-details/mediaDetailPrefetch";
    import MediaPoster from "$entities/media/ui/MediaPoster.svelte";
    import MediaScoreBadge from "$entities/media/ui/MediaScoreBadge.svelte";
    import MediaStatusBadge from "$entities/media/ui/MediaStatusBadge.svelte";
    import { createCardStatus } from "$features/change-status/statusController.svelte";

    interface Props {
        item: MediaItem;
        onOpen?: (item: MediaItem) => void;
        onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
        onProgressCommitted?: () => void;
        onDelete?: (item: MediaItem) => Promise<void>;
        /** Rendered below the poster: title, progress, type-specific controls. */
        children: Snippet;
    }

    let {
        item,
        onOpen = () => {},
        onStatusChange,
        onProgressCommitted = () => {},
        onDelete,
        children,
    }: Props = $props();

    let deleteError = $state<unknown>(null);

    const status = createCardStatus({
        getItem: () => item,
        getOnStatusChange: () => onStatusChange,
        getOnProgressCommitted: () => onProgressCommitted,
    });

    function handleKeydown(event: KeyboardEvent) {
        if (event.target !== event.currentTarget) return;
        if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            onOpen(item);
        }
    }

    async function removeItem() {
        if (!onDelete || !window.confirm(i18n.t.card.confirmDelete(item.title)))
            return;

        deleteError = null;
        try {
            await onDelete(item);
        } catch (error) {
            deleteError = error;
        }
    }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_to_interactive_role -->
<article
    class="media-card @container group relative cursor-pointer rounded-xl border border-white/[0.05] bg-card p-2.5 shadow-lg transition-all hover:border-white/[0.1] hover:bg-card-hover focus-within:ring-2 focus-within:ring-indigo-500/30"
    role="button"
    tabindex="0"
    aria-label={i18n.t.card.openDetails(item.title)}
    onclick={() => onOpen(item)}
    onpointerenter={() => schedulePrefetchMediaDetail(item.id)}
    onfocus={() => schedulePrefetchMediaDetail(item.id)}
    onkeydown={handleKeydown}
>
    <MediaPoster src={item.coverUrl} alt={item.title}>
        {#snippet badges()}
            <MediaStatusBadge
                id={`status-${item.id}`}
                status={item.status}
                onSelect={(next) => void status.changeStatus(next)}
            />
            <MediaScoreBadge score={item.score} />
        {/snippet}

        {#snippet actions()}
            <button
                type="button"
                class="tap grid h-7 w-7 place-items-center rounded-full border border-white/[0.06] bg-black/60 text-white/70 opacity-0 shadow-md backdrop-blur-md transition hover:border-rose-500/40 hover:bg-rose-600 hover:text-white focus:opacity-100 group-hover:opacity-100 cursor-pointer"
                aria-label={i18n.t.card.deleteAria(item.title)}
                onclick={(event) => {
                    event.stopPropagation();
                    void removeItem();
                }}
            >
                <Trash2 size={14} aria-hidden="true" />
            </button>
        {/snippet}
    </MediaPoster>

    <div class="relative z-10 min-w-0 space-y-3 px-0.5 pb-1 pt-3">
        {@render children()}

        {#if deleteError}
            <p class="text-xs leading-4 text-rose-300" role="alert">
                {errorMessage(deleteError)}
            </p>
        {/if}
    </div>
</article>