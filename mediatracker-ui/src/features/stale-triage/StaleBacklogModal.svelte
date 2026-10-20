<script lang="ts">
    import Modal from "$shared/ui/Modal.svelte";
    import {
        Hourglass,
        X,
        Flame,
        Pause,
        Ban,
        Bookmark,
        Image as ImageIcon,
    } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import {
        MEDIA_STATUS,
        type MediaItem,
    } from "$shared/types";
    import {
        getDaysInactive,
        isStaleInProgress,
        type StaleThresholdDays,
    } from "$entities/media/model/staleTriage";
    import { cardTypeLabel } from "$entities/media/model/mediaLabels";
    import { getMedia, updateMedia, updateStatus, errorMessage } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";

    interface Props {
        isOpen: boolean;
        onClose: () => void;
        items?: MediaItem[];
        onMediaChanged?: () => void;
    }

    let { isOpen, onClose, items, onMediaChanged }: Props = $props();

    let threshold = $state<StaleThresholdDays>(180);
    let allInProgress = $state<MediaItem[]>([]);
    let loading = $state(false);

    $effect(() => {
        if (!isOpen) return;

        if (items) {
            allInProgress = [...items];
        } else {
            loading = true;
            getMedia({ status: MEDIA_STATUS.inProgress })
                .then((res) => {
                    allInProgress = res;
                })
                .catch((e) => {
                    showToast(errorMessage(e), "error");
                })
                .finally(() => {
                    loading = false;
                });
        }
    });

    const thresholdOptions: { value: StaleThresholdDays; label: string }[] = $derived([
        { value: 90, label: i18n.t.staleTriage.threshold90 },
        { value: 180, label: i18n.t.staleTriage.threshold180 },
        { value: 365, label: i18n.t.staleTriage.threshold365 },
    ]);

    const staleItems = $derived(
        allInProgress.filter((item) => isStaleInProgress(item, threshold))
    );

    function formatProgress(item: MediaItem): string {
        if (item.type === "tvshow") {
            const cur = item.totalEpisodesWatched;
            const tot = item.totalEpisodesCount;
            const pct = tot > 0 ? ` (${Math.round((cur / tot) * 100)}%)` : "";
            return `${i18n.t.card.episodes(cur, tot)}${pct}`;
        }
        if (item.type === "book") {
            const cur = item.currentPage;
            const tot = item.totalPages;
            const pct = tot > 0 ? ` (${Math.round((cur / tot) * 100)}%)` : "";
            return `${i18n.t.card.pages(cur, tot)}${pct}`;
        }
        if (item.type === "manga") {
            const cur = item.currentChapter;
            const tot = item.totalChapters;
            const pct = tot && tot > 0 ? ` (${Math.round((cur / tot) * 100)}%)` : "";
            return `${i18n.t.card.chapters(cur, tot)}${pct}`;
        }
        if (item.type === "game") {
            return i18n.t.card.hours(item.hoursPlayed ?? 0);
        }
        if (item.type === "movie") {
            return item.durationMinutes ? i18n.t.card.movie(item.durationMinutes) : "";
        }
        return "";
    }

    function formatDate(rawDate: string | null | undefined): string {
        if (!rawDate) return "—";
        const d = new Date(rawDate);
        if (isNaN(d.getTime())) return "—";
        return new Intl.DateTimeFormat(i18n.current, {
            day: "numeric",
            month: "short",
            year: "numeric",
        }).format(d);
    }

    async function handleFocus(item: MediaItem) {
        allInProgress = allInProgress.filter((x) => x.id !== item.id);
        showToast(i18n.t.staleTriage.toastFocus, "success");
        try {
            await updateMedia(item.id, { lastActivityAt: new Date().toISOString() });
            onMediaChanged?.();
        } catch (e) {
            showToast(errorMessage(e), "error");
        }
    }

    async function handlePause(item: MediaItem) {
        allInProgress = allInProgress.filter((x) => x.id !== item.id);
        showToast(i18n.t.staleTriage.toastOnHold, "success");
        try {
            await updateStatus(item.id, MEDIA_STATUS.onHold);
            onMediaChanged?.();
        } catch (e) {
            showToast(errorMessage(e), "error");
        }
    }

    async function handleDrop(item: MediaItem) {
        allInProgress = allInProgress.filter((x) => x.id !== item.id);
        showToast(i18n.t.staleTriage.toastDropped, "success");
        try {
            await updateStatus(item.id, MEDIA_STATUS.dropped);
            onMediaChanged?.();
        } catch (e) {
            showToast(errorMessage(e), "error");
        }
    }

    async function handleToPlanned(item: MediaItem) {
        allInProgress = allInProgress.filter((x) => x.id !== item.id);
        showToast(i18n.t.staleTriage.toastPlanned, "success");
        try {
            await updateStatus(item.id, MEDIA_STATUS.planned);
            onMediaChanged?.();
        } catch (e) {
            showToast(errorMessage(e), "error");
        }
    }
</script>

<Modal {isOpen} {onClose} size="lg">
    <div class="flex flex-col max-h-[85vh]">
        <!-- Шапка окна -->
        <div class="flex items-center justify-between border-b border-white/5 px-6 py-4 shrink-0">
            <div class="flex items-center gap-3">
                <div class="grid h-10 w-10 place-items-center rounded-xl bg-amber-500/10 text-amber-400 border border-amber-500/20">
                    <Hourglass size={20} aria-hidden="true" />
                </div>
                <div>
                    <h3 class="text-base font-bold text-white">
                        {i18n.t.staleTriage.staleTriageTitle}
                    </h3>
                    <p class="text-xs text-muted">
                        {i18n.t.staleTriage.staleTriageSubtitle}
                    </p>
                </div>
            </div>
            <button
                type="button"
                class="grid h-8 w-8 place-items-center rounded-lg text-muted hover:text-white hover:bg-white/5 transition cursor-pointer"
                onclick={onClose}
                aria-label={i18n.t.common.close}
            >
                <X size={18} />
            </button>
        </div>

        <!-- Панель фильтра порога неактивности -->
        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-white/5 px-6 py-3 bg-white/[0.01] shrink-0">
            <div class="flex items-center gap-1.5">
                {#each thresholdOptions as opt}
                    <button
                        type="button"
                        class="rounded-lg px-3 py-1 text-xs font-medium transition cursor-pointer {threshold === opt.value
                            ? 'bg-accent text-white shadow-sm'
                            : 'bg-white/5 text-slate-300 hover:bg-white/10 hover:text-white'}"
                        onclick={() => (threshold = opt.value)}
                    >
                        {opt.label}
                    </button>
                {/each}
            </div>
            <div class="text-xs text-slate-400">
                {i18n.t.staleTriage.foundCount(staleItems.length)}
            </div>
        </div>

        <!-- Список карточек для ревизии -->
        <div class="flex-1 overflow-y-auto space-y-3 p-6 min-h-[220px]">
            {#if loading}
                <div class="flex items-center justify-center py-12 text-muted text-sm">
                    {i18n.t.common.loading}
                </div>
            {:else if staleItems.length === 0}
                <!-- Экран успеха -->
                <div class="flex flex-col items-center justify-center gap-3 py-12 text-center">
                    <div class="grid h-14 w-14 place-items-center rounded-2xl bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 text-2xl">
                        🎉
                    </div>
                    <div>
                        <h4 class="text-base font-bold text-white">
                            {i18n.t.staleTriage.triageCompleteTitle}
                        </h4>
                        <p class="mt-1.5 max-w-md text-xs text-slate-400 leading-relaxed">
                            {i18n.t.staleTriage.triageCompleteText(threshold)}
                        </p>
                    </div>
                </div>
            {:else}
                {#each staleItems as item (item.id)}
                    {@const rawDate = item.lastActivityAt || item.startedAt || item.createdAt}
                    {@const days = getDaysInactive(item)}
                    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 rounded-xl border border-white/5 bg-white/[0.02] p-3.5 hover:border-white/10 transition">
                        <!-- Слева: мини-постер и инфо посередине -->
                        <div class="flex items-center gap-3.5 min-w-0">
                            {#if item.coverUrl}
                                <img
                                    src={item.coverUrl}
                                    alt={item.title}
                                    class="aspect-[2/3] w-14 rounded-lg object-cover shrink-0 bg-white/5"
                                    loading="lazy"
                                />
                            {:else}
                                <div class="aspect-[2/3] w-14 rounded-lg bg-white/5 flex items-center justify-center text-muted shrink-0">
                                    <ImageIcon size={20} aria-hidden="true" />
                                </div>
                            {/if}

                            <div class="min-w-0 space-y-1">
                                <div class="flex items-center gap-2 flex-wrap">
                                    <h4 class="font-semibold text-sm text-white truncate max-w-sm" title={item.title}>
                                        {item.title}
                                    </h4>
                                    <span class="rounded-md bg-white/5 px-2 py-0.5 text-[11px] font-medium text-slate-300 border border-white/10 shrink-0">
                                        {cardTypeLabel(item)}
                                    </span>
                                </div>

                                {#if formatProgress(item)}
                                    <p class="text-xs text-slate-400 font-medium">
                                        {formatProgress(item)}
                                    </p>
                                {/if}

                                <p class="text-xs text-amber-400/95 font-medium">
                                    {i18n.t.staleTriage.daysInactive(days, formatDate(rawDate))}
                                </p>
                            </div>
                        </div>

                        <!-- Справа — кнопки быстрых действий в 1 клик -->
                        <div class="flex items-center gap-2 shrink-0 self-end sm:self-center">
                            <button
                                type="button"
                                class="flex items-center gap-1.5 rounded-lg border border-orange-500/20 bg-orange-500/10 px-2.5 py-1.5 text-xs font-semibold text-orange-400 hover:bg-orange-500/20 hover:border-orange-500/40 transition cursor-pointer"
                                title={i18n.t.staleTriage.actionFocus}
                                onclick={() => handleFocus(item)}
                            >
                                <Flame size={15} />
                                <span class="hidden md:inline">{i18n.t.staleTriage.actionFocus}</span>
                            </button>

                            <button
                                type="button"
                                class="flex items-center gap-1.5 rounded-lg border border-amber-500/20 bg-amber-500/10 px-2.5 py-1.5 text-xs font-semibold text-amber-400 hover:bg-amber-500/20 hover:border-amber-500/40 transition cursor-pointer"
                                title={i18n.t.staleTriage.actionOnHold}
                                onclick={() => handlePause(item)}
                            >
                                <Pause size={15} />
                                <span class="hidden md:inline">{i18n.t.staleTriage.actionOnHold}</span>
                            </button>

                            <button
                                type="button"
                                class="flex items-center gap-1.5 rounded-lg border border-rose-500/20 bg-rose-500/10 px-2.5 py-1.5 text-xs font-semibold text-rose-400 hover:bg-rose-500/20 hover:border-rose-500/40 transition cursor-pointer"
                                title={i18n.t.staleTriage.actionDrop}
                                onclick={() => handleDrop(item)}
                            >
                                <Ban size={15} />
                                <span class="hidden md:inline">{i18n.t.staleTriage.actionDrop}</span>
                            </button>

                            <button
                                type="button"
                                class="flex items-center gap-1.5 rounded-lg border border-blue-500/20 bg-blue-500/10 px-2.5 py-1.5 text-xs font-semibold text-blue-400 hover:bg-blue-500/20 hover:border-blue-500/40 transition cursor-pointer"
                                title={i18n.t.staleTriage.actionToPlanned}
                                onclick={() => handleToPlanned(item)}
                            >
                                <Bookmark size={15} />
                                <span class="hidden md:inline">{i18n.t.staleTriage.actionToPlanned}</span>
                            </button>
                        </div>
                    </div>
                {/each}
            {/if}
        </div>
    </div>
</Modal>
