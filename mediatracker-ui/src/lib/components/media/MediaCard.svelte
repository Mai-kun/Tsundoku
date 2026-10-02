<script lang="ts">
    import Bookmark from "lucide-svelte/icons/bookmark";
    import Check from "lucide-svelte/icons/check";
    import ChevronDown from "lucide-svelte/icons/chevron-down";
    import ImageIcon from "lucide-svelte/icons/image";
    import Minus from "lucide-svelte/icons/minus";
    import Pause from "lucide-svelte/icons/pause";
    import Play from "lucide-svelte/icons/play";
    import Plus from "lucide-svelte/icons/plus";
    import Trash2 from "lucide-svelte/icons/trash-2";
    import X from "lucide-svelte/icons/x";
    import { untrack } from "svelte";
    import { errorMessage, updateStatus } from "$lib/api";
    import { i18n } from "$lib/i18n/index.svelte";
    import {
        clampProgress,
        MEDIA_STATUS,
        type MediaItem,
        type MediaStatus,
    } from "$lib/types";
    import { createProgressDebounce } from "$lib/utils/progressDebounce";
    import { schedulePrefetchMediaDetail } from "$lib/utils/mediaDetailPrefetch";
    import PopoverMenu from "$lib/components/ui/PopoverMenu.svelte";

    interface Props {
        item: MediaItem;
        onOpen?: (item: MediaItem) => void;
        onProgress?: (id: string, currentProgress: number) => Promise<void>;
        onProgressCommitted?: () => void;
        onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
        onDelete?: (item: MediaItem) => Promise<void>;
        onEdit?: (item: MediaItem) => void;
        onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
    }

    let {
        item,
        onOpen = () => {},
        onProgress,
        onProgressCommitted = () => {},
        onStatusChange,
        onDelete,
        onEdit = () => {},
        onEpisodeStep,
    }: Props = $props();

    let trackedItem: MediaItem | null = null;
    let currentProgress = $state(untrack(() => readProgress(item)));
    let committedProgress = $state(untrack(() => currentProgress));
    let pendingSnapshot = $state<number | null>(null);

    let progressError = $state<unknown>(null);
    let deleteError = $state<unknown>(null);

    const statusOptions: readonly MediaStatus[] = [
        MEDIA_STATUS.planned,
        MEDIA_STATUS.inProgress,
        MEDIA_STATUS.completed,
        MEDIA_STATUS.onHold,
        MEDIA_STATUS.dropped,
    ];

    const statusMenuItems = $derived(
        statusOptions.map((value) => ({ value, label: statusLabel(value) })),
    );

    async function changeStatus(newStatus: MediaStatus) {
        const prevStatus = item.status;
        item.status = newStatus;
        if (onStatusChange) {
            onStatusChange(item, newStatus);
        }
        try {
            await updateStatus(item.id, newStatus);
            onProgressCommitted();
        } catch (e) {
            item.status = prevStatus;
            if (onStatusChange) {
                onStatusChange(item, prevStatus);
            }
            console.error(e);
        }
    }

    const progressDebounce = createProgressDebounce({
        send: (id, value) => (onProgress ?? (async () => {}))(id, value),
        buildRequest: (id, value) => ({
            url: `/api/media/${id}/progress`,
            body: { currentProgress: value },
        }),
        onCommitted: (value) => {
            committedProgress = value;
            if (currentProgress === value) onProgressCommitted();
        },
        onError: (error) => {
            currentProgress = pendingSnapshot ?? committedProgress;
            committedProgress = currentProgress;
            pendingSnapshot = null;
            progressError = error;
        },
    });

    $effect(() => {
        if (item !== trackedItem) {
            trackedItem = item;
            currentProgress = readProgress(item);
            committedProgress = currentProgress;
            pendingSnapshot = null;
        }
    });

    $effect(() => {
        return () => void progressDebounce.flush(true);
    });

    function readProgress(media: MediaItem): number {
        switch (media.type) {
            case "game":
                return media.hoursPlayed ?? 0;
            case "book":
                return media.currentPage;
            case "manga":
                return media.currentChapter;
            default:
                return 0;
        }
    }

    function totalForProgress(media: MediaItem): number | null {
        switch (media.type) {
            case "book":
                return media.totalPages;
            case "manga":
                return media.totalChapters;
            default:
                return null;
        }
    }

    function statusLabel(status: MediaStatus): string {
        switch (status) {
            case 0:
                return i18n.t.status.planned;
            case 1:
                return i18n.t.status.inProgress;
            case 2:
                return i18n.t.status.completed;
            case 3:
                return i18n.t.status.paused;
            case 4:
                return i18n.t.status.dropped;
        }
    }

    function statusBadgeClasses(status: MediaStatus): string {
        switch (status) {
            case MEDIA_STATUS.inProgress:
                return "border-[#5844e0]/50 bg-[#5844e0]/30 text-[#a5b4fc]";
            case MEDIA_STATUS.completed:
                return "border-emerald-700/50 bg-emerald-950/80 text-emerald-300";
            case MEDIA_STATUS.onHold:
                return "border-amber-700/50 bg-amber-950/80 text-amber-300";
            case MEDIA_STATUS.dropped:
                return "border-rose-700/50 bg-rose-950/80 text-rose-300";
            default:
                return "border-zinc-700/50 bg-zinc-800/80 text-zinc-300";
        }
    }

    function format(value: number): string {
        return new Intl.NumberFormat(i18n.current).format(value);
    }

    /**
     * Games list every platform the release shipped on; the only one that means
     * something to the user is the one they picked.
     */
    function cardPlatform(media: MediaItem): string | null {
        if (media.type !== "game") return null;
        return media.userPlatform?.trim() || media.platform?.trim() || null;
    }

    function cardTypeLabel(media: MediaItem): string {
        if (media.type === "tvshow" && media.isAnime) {
            return i18n.t.navigation.anime;
        }

        return i18n.t.types[media.type];
    }

    function progressLabel(media: MediaItem): string | null {
        switch (media.type) {
            case "game":
                return i18n.t.card.hours(currentProgress);
            case "book":
                return i18n.t.card.pages(currentProgress, media.totalPages);
            case "manga":
                return i18n.t.card.chapters(
                    currentProgress,
                    media.totalChapters,
                );
            case "movie":
                return i18n.t.card.movie(media.durationMinutes);
            case "tvshow":
                return i18n.t.card.episodes(
                    media.totalEpisodesWatched,
                    media.totalEpisodesCount,
                );
        }
    }

    function progressRatio(media: MediaItem): number | null {
        const total =
            media.type === "tvshow"
                ? media.totalEpisodesCount
                : totalForProgress(media);
        const current =
            media.type === "tvshow"
                ? media.totalEpisodesWatched
                : currentProgress;

        return total !== null && total > 0
            ? Math.min(current / total, 1)
            : null;
    }

    function scheduleProgress(delta: number) {
        if (!onProgress || !supportsStepper(item)) return;

        const next = clampProgress(
            currentProgress + delta,
            totalForProgress(item),
        );
        if (next === currentProgress) return;

        if (pendingSnapshot === null) {
            pendingSnapshot = committedProgress;
        }

        currentProgress = next;
        progressError = null;
        progressDebounce.schedule(item.id, next);
    }

    function handleCardKeydown(event: KeyboardEvent) {
        if (event.target !== event.currentTarget) return;

        if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            onOpen(item);
        }
    }

    function supportsStepper(media: MediaItem): boolean {
        if (media.status !== MEDIA_STATUS.inProgress) return false;
        return (
            media.type === "game" ||
            media.type === "book" ||
            media.type === "manga"
        );
    }

    async function stepEpisode(delta: number) {
        if (!onEpisodeStep || item.type !== "tvshow") return;
        await onEpisodeStep(item, delta);
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
    class="@container group relative cursor-pointer rounded-xl border border-white/[0.05] bg-card p-2.5 shadow-lg transition-all hover:border-white/[0.1] hover:bg-card-hover focus-within:ring-2 focus-within:ring-indigo-500/30"
    style="content-visibility: auto; contain-intrinsic-size: auto 300px;"
    role="button"
    tabindex="0"
    aria-label={i18n.t.card.openDetails(item.title)}
    onclick={() => onOpen(item)}
    onpointerenter={() => schedulePrefetchMediaDetail(item.id)}
    onfocus={() => schedulePrefetchMediaDetail(item.id)}
    onkeydown={handleCardKeydown}
>
    <div class="aspect-[3/4] overflow-hidden rounded-lg bg-canvas">
        {#if item.coverUrl}
            <img
                src={item.coverUrl}
                alt={item.title}
                class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
                loading="lazy"
                decoding="async"
            />
        {:else}
            <div
                class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-muted"
            >
                <ImageIcon size={38} stroke-width={1.25} aria-hidden="true" />
            </div>
        {/if}

        <div
            class="absolute inset-x-0 top-0 z-10 flex items-start justify-between gap-2 p-2.5"
        >
            <!-- Status + rating as one overlapping cluster in the poster's top-left corner.
           The score circle pulls left (-ml-2) so the pair reads as a single unit and
           sits on the same level as the status badge; it mirrors the badge's shape. -->
            <div class="relative flex items-center">
                <PopoverMenu
                    id={`status-${item.id}`}
                    options={statusMenuItems}
                    selected={item.status}
                    onSelect={(value) =>
                        void changeStatus(value as MediaStatus)}
                    label={i18n.t.status.label}
                    openOnHover
                    closeDelay={220}
                >
                    {#snippet trigger({ popoverTargetId, anchorName })}
                        <button
                            type="button"
                            popovertarget={popoverTargetId}
                            popovertargetaction="toggle"
                            style="anchor-name: {anchorName}"
                            class="tap grid h-[2.33rem] w-[2.33rem] shrink-0 place-items-center p-0 rounded-full border shadow-lg backdrop-blur transition hover:brightness-125 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-400/70 {statusBadgeClasses(
                                item.status,
                            )}"
                            title={statusLabel(item.status)}
                            aria-label={statusLabel(item.status)}
                        >
                            {#if item.status === MEDIA_STATUS.planned}
                                <Bookmark
                                    size={20}
                                    stroke-width={2.5}
                                    aria-hidden="true"
                                />
                            {:else if item.status === MEDIA_STATUS.inProgress}
                                <Play
                                    size={20}
                                    fill="currentColor"
                                    aria-hidden="true"
                                />
                            {:else if item.status === MEDIA_STATUS.completed}
                                <Check
                                    size={21}
                                    stroke-width={3}
                                    aria-hidden="true"
                                />
                            {:else if item.status === MEDIA_STATUS.onHold}
                                <Pause
                                    size={21}
                                    stroke-width={2.5}
                                    aria-hidden="true"
                                />
                            {:else if item.status === MEDIA_STATUS.dropped}
                                <X
                                    size={24}
                                    stroke-width={4}
                                    aria-hidden="true"
                                />
                            {/if}
                        </button>
                    {/snippet}
                </PopoverMenu>

                <!-- Only rendered once the user has rated: an always-on bubble with a placeholder star
                     read as a real, unrated value on the card. -->
                {#if item.score !== null && item.score > 0}
                    <div
                        class="relative z-10 -ml-2 grid h-[2.33rem] w-[2.33rem] place-items-center rounded-full bg-score-bg text-[17px] font-black tabular-nums tracking-tight text-white shadow-lg select-none"
                        title={`${i18n.t.createModal.fields.score}: ${item.score}`}
                    >
                        {format(item.score)}
                    </div>
                {/if}
            </div>

            <div class="flex items-center gap-1.5">
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
            </div>
        </div>
    </div>

    <div class="relative z-10 min-w-0 space-y-3 px-0.5 pb-1 pt-3">
        <div class="min-w-0">
            <h2
                class="truncate break-words text-sm font-semibold text-ink"
                title={item.title.length > 100
                    ? item.title.slice(0, 97) + "..."
                    : item.title}
            >
                {item.title}
            </h2>
            <p class="mt-1 truncate text-xs text-muted @max-[13rem]:hidden">
                {#if cardPlatform(item)}
                    {cardPlatform(item)}
                {:else if item.type === "book" && item.author}
                    {item.author}
                {:else}
                    {cardTypeLabel(item)}
                    {#if item.type === "tvshow" && item.seasonsCount > 0}
                        • {item.seasonsCount}
                    {/if}
                {/if}
            </p>
        </div>

        {#if progressLabel(item)}
            <div class="space-y-1.5">
                <div
                    class="flex items-center justify-between gap-2 text-xs text-muted"
                >
                    <span>{progressLabel(item)}</span>
                </div>
                {#if progressRatio(item) !== null}
                    <div class="h-1.5 overflow-hidden rounded-full bg-canvas">
                        <div
                            class="h-full rounded-full bg-accent transition-[width] duration-200"
                            style={`width: ${progressRatio(item)! * 100}%`}
                        ></div>
                    </div>
                {:else if supportsStepper(item)}
                    <div class="h-1.5" aria-hidden="true"></div>
                {/if}
            </div>
        {/if}

        {#if supportsStepper(item)}
            <div class="flex h-8 items-center rounded-md bg-canvas">
                <button
                    type="button"
                    class="tap grid h-full w-8 place-items-center rounded-l-md text-muted transition hover:bg-panel hover:text-ink"
                    aria-label={i18n.t.card.decrement}
                    onclick={(event) => {
                        event.stopPropagation();
                        scheduleProgress(-1);
                    }}><Minus size={14} aria-hidden="true" /></button
                >
                <span
                    class="flex-1 text-center text-xs font-semibold tabular-nums text-ink"
                    >{format(currentProgress)}</span
                >
                <button
                    type="button"
                    class="tap grid h-full w-8 place-items-center rounded-r-md text-muted transition hover:bg-panel hover:text-ink"
                    aria-label={i18n.t.card.increment}
                    onclick={(event) => {
                        event.stopPropagation();
                        scheduleProgress(1);
                    }}><Plus size={14} aria-hidden="true" /></button
                >
            </div>
        {/if}

        {#if item.type === "tvshow" && onEpisodeStep && item.status === MEDIA_STATUS.inProgress && item.totalEpisodesCount !== 1}
            <div class="flex h-8 items-center rounded-md bg-canvas">
                <button
                    type="button"
                    class="tap grid h-full w-8 place-items-center rounded-l-md text-muted transition hover:bg-panel hover:text-ink disabled:opacity-40"
                    aria-label={i18n.t.card.decrement}
                    disabled={item.totalEpisodesWatched <= 0}
                    onclick={(event) => {
                        event.stopPropagation();
                        void stepEpisode(-1);
                    }}><Minus size={14} aria-hidden="true" /></button
                >
                <span
                    class="flex-1 text-center text-xs font-semibold tabular-nums text-ink"
                >
                    {item.totalEpisodesWatched}{item.totalEpisodesCount > 0
                        ? ` / ${item.totalEpisodesCount}`
                        : ""}
                </span>
                <button
                    type="button"
                    class="tap grid h-full w-8 place-items-center rounded-r-md text-muted transition hover:bg-panel hover:text-ink disabled:opacity-40"
                    aria-label={i18n.t.card.increment}
                    disabled={item.totalEpisodesCount > 0 &&
                        item.totalEpisodesWatched >= item.totalEpisodesCount}
                    onclick={(event) => {
                        event.stopPropagation();
                        void stepEpisode(1);
                    }}><Plus size={14} aria-hidden="true" /></button
                >
            </div>
        {/if}

        {#if progressError}
            <p class="text-xs leading-4 text-rose-300" role="alert">
                {errorMessage(progressError)}
            </p>
        {/if}
        {#if deleteError}
            <p class="text-xs leading-4 text-rose-300" role="alert">
                {errorMessage(deleteError)}
            </p>
        {/if}
    </div>
</article>
