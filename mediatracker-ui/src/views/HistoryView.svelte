<script lang="ts">
    import {
        ArrowUpRight,
        CalendarDays,
        History,
        LoaderCircle,
        RefreshCw,
        Trash2,
        Flag,
        Trophy,
    } from "$shared/ui/Icons.svelte";
    import {
        clearAllHistory,
        deleteHistoryEvent,
        errorMessage,
        getHistoryEvents,
        getMedia,
    } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { HistoryEvent, MediaItem } from "$shared/types";
    import {
        formatHistoryEventLabel,
        HISTORY_EVENT_ICONS,
    } from "$shared/utils/historyFormatters";
    import {
        buildChronicle,
        type TimelineScale,
        type TimelineCategoryFilter,
    } from "$entities/media/model/chronicleTimeline";

    interface Props {
        refreshKey: number;
        onOpenMedia?: (mediaId: string) => void;
    }

    let { refreshKey, onOpenMedia }: Props = $props();

    // ── Tab state ──────────────────────────────────────────────────────────
    type Tab = "chronicle" | "activity";
    let activeTab = $state<Tab>("chronicle");

    // ── Activity tab state ─────────────────────────────────────────────────
    let selectedDate = $state("");
    let events = $state<HistoryEvent[]>([]);
    let loadingEvents = $state(true);
    let loadEventsError = $state<unknown>(null);
    let clearing = $state(false);
    let deletingId = $state<string | null>(null);
    let eventsSequence = 0;

    $effect(() => {
        void refreshKey;
        void selectedDate;
        void activeTab;
        if (activeTab === "activity") void loadEvents(++eventsSequence);
    });

    async function loadEvents(sequence: number) {
        loadingEvents = true;
        loadEventsError = null;
        try {
            const nextEvents = await getHistoryEvents({ date: selectedDate || undefined });
            if (sequence === eventsSequence) events = nextEvents;
        } catch (error) {
            if (sequence === eventsSequence) loadEventsError = error;
        } finally {
            if (sequence === eventsSequence) loadingEvents = false;
        }
    }

    function retryEvents() { void loadEvents(++eventsSequence); }

    function formatDate(value: string): string {
        return new Intl.DateTimeFormat(i18n.current, {
            dateStyle: "medium",
            timeStyle: "short",
        }).format(new Date(value));
    }

    async function handleDeleteEvent(event: HistoryEvent) {
        if (deletingId !== null) return;
        if (!window.confirm(i18n.t.views.confirmDeleteHistoryEntry)) return;
        deletingId = event.id;
        const prevEvents = events;
        events = events.filter((x) => x.id !== event.id);
        try {
            await deleteHistoryEvent(event.id);
            showToast(i18n.t.views.historyEntryDeleted, "success");
        } catch (err) {
            events = prevEvents;
            showToast(errorMessage(err), "error");
        } finally {
            deletingId = null;
        }
    }

    async function handleClearAll() {
        if (events.length === 0) return;
        if (!window.confirm(i18n.t.views.confirmClearHistory)) return;
        clearing = true;
        const prevEvents = events;
        events = [];
        try {
            await clearAllHistory();
            showToast(i18n.t.views.historyCleared, "success");
        } catch (err) {
            events = prevEvents;
            showToast(errorMessage(err), "error");
        } finally {
            clearing = false;
        }
    }

    // ── Chronicle tab state ────────────────────────────────────────────────
    let scale = $state<TimelineScale>("months");
    let categoryFilter = $state<TimelineCategoryFilter>("all");
    let includeInProgress = $state(false);

    let allItems = $state<MediaItem[]>([]);
    let loadingItems = $state(true);
    let loadItemsError = $state<unknown>(null);
    let itemsSequence = 0;

    $effect(() => {
        void refreshKey;
        void loadAllItems(++itemsSequence);
    });

    async function loadAllItems(sequence: number) {
        loadingItems = true;
        loadItemsError = null;
        try {
            const data = await getMedia();
            if (sequence === itemsSequence) allItems = data;
        } catch (err) {
            if (sequence === itemsSequence) loadItemsError = err;
        } finally {
            if (sequence === itemsSequence) loadingItems = false;
        }
    }

    function retryItems() { void loadAllItems(++itemsSequence); }

    const chronicle = $derived(
        buildChronicle(allItems, { category: categoryFilter, includeInProgress }),
    );

    // Month name formatter
    function monthName(month: number): string {
        return new Intl.DateTimeFormat(i18n.current, { month: "long" }).format(
            new Date(2000, month, 1),
        );
    }

    // Short date for card footer (e.g. "14 окт.")
    function shortDate(date: Date): string {
        return new Intl.DateTimeFormat(i18n.current, {
            day: "numeric",
            month: "short",
        }).format(date);
    }

    // Type label for card
    function typeLabel(item: MediaItem): string {
        const base = i18n.t.types[item.type as keyof typeof i18n.t.types] as string;
        const isAnime = (item as { isAnime?: boolean }).isAnime;
        if (isAnime && (item.type === "tvshow" || item.type === "movie")) {
            return i18n.t.navigation.anime as string;
        }
        return base;
    }

    const CATEGORY_CHIPS: { key: TimelineCategoryFilter; label: () => string }[] = [
        { key: "all", label: () => i18n.t.status.all as string },
        { key: "game", label: () => i18n.t.navigation.game as string },
        { key: "anime", label: () => i18n.t.navigation.anime as string },
        { key: "manga", label: () => i18n.t.navigation.manga as string },
        { key: "movie", label: () => i18n.t.navigation.movie as string },
        { key: "tvshow", label: () => i18n.t.navigation.tvshow as string },
        { key: "book", label: () => i18n.t.navigation.book as string },
    ];

    function scrollToYear(year: number) {
        document.getElementById(`chronicle-year-${year}`)?.scrollIntoView({
            behavior: "smooth",
            block: "start",
        });
    }
</script>

<div class="mx-auto max-w-5xl space-y-6">
    <!-- ── Page header + tab switcher ─────────────────────────────────── -->
    <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">
                {i18n.t.library.collectionLabel}
            </p>
            <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">
                {i18n.t.views.historyTitle}
            </h2>
        </div>

        <!-- Activity-only controls (date filter + clear) -->
        {#if activeTab === "activity"}
            <div class="flex flex-wrap items-center gap-2">
                <div class="flex items-center gap-1.5">
                    <input
                        type="date"
                        bind:value={selectedDate}
                        class="h-8 rounded-lg border border-white/10 bg-field px-2.5 text-xs text-white outline-none focus:border-accent focus:ring-1 focus:ring-accent transition cursor-pointer"
                        aria-label={i18n.t.views.filterByDate}
                    />
                    {#if selectedDate}
                        <button
                            type="button"
                            class="h-8 rounded-lg border border-white/10 bg-field px-2.5 text-xs text-muted hover:text-white transition cursor-pointer"
                            onclick={() => (selectedDate = "")}
                        >
                            {i18n.t.views.resetDate}
                        </button>
                    {/if}
                </div>
                {#if events.length > 0}
                    <button
                        type="button"
                        class="inline-flex items-center gap-1.5 rounded-md border border-white/10 bg-field px-3 py-1.5 text-xs font-semibold text-rose-400 transition hover:bg-rose-500/10 hover:border-rose-500/40 cursor-pointer disabled:opacity-50"
                        disabled={clearing}
                        onclick={handleClearAll}
                    >
                        <Trash2 size={13} />
                        <span>{i18n.t.views.clearHistory}</span>
                    </button>
                {/if}
            </div>
        {/if}
    </div>

    <!-- ── Tab switcher pills ────────────────────────────────────────────── -->
    <div class="flex gap-1 rounded-xl bg-card p-1 w-fit">
        <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold transition cursor-pointer {activeTab === 'chronicle'
                ? 'bg-accent text-white shadow-sm'
                : 'text-muted hover:text-ink'}"
            onclick={() => (activeTab = "chronicle")}
        >
            <CalendarDays size={15} aria-hidden="true" />
            {i18n.t.views.tabChronicle}
        </button>
        <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold transition cursor-pointer {activeTab === 'activity'
                ? 'bg-accent text-white shadow-sm'
                : 'text-muted hover:text-ink'}"
            onclick={() => (activeTab = "activity")}
        >
            <History size={15} aria-hidden="true" />
            {i18n.t.views.tabActivity}
        </button>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════════ -->
    <!-- CHRONICLE TAB                                                       -->
    <!-- ═══════════════════════════════════════════════════════════════════ -->
    {#if activeTab === "chronicle"}
        {#if loadingItems}
            <div class="space-y-4" aria-hidden="true">
                {#each Array(3) as _, i (i)}
                    <div class="h-40 animate-pulse rounded-xl bg-card"></div>
                {/each}
            </div>
            <p class="sr-only" role="status">{i18n.t.common.loading}</p>
        {:else if loadItemsError}
            <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center">
                <p class="text-sm text-rose-200" role="alert">{errorMessage(loadItemsError)}</p>
                <button
                    type="button"
                    class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                    onclick={retryItems}
                >
                    <RefreshCw size={15} aria-hidden="true" />
                    {i18n.t.common.retry}
                </button>
            </div>
        {:else}
            <!-- Chronicle controls -->
            <div class="flex flex-wrap items-center gap-3">
                <!-- Scale toggle -->
                <div class="flex gap-1 rounded-lg bg-card p-0.5">
                    {#each [{ v: "months" as TimelineScale, label: i18n.t.views.scaleMonths }, { v: "years" as TimelineScale, label: i18n.t.views.scaleYears }] as opt (opt.v)}
                        <button
                            type="button"
                            class="rounded-md px-3 py-1.5 text-xs font-semibold transition cursor-pointer {scale === opt.v
                                ? 'bg-accent/20 text-accent-soft'
                                : 'text-muted hover:text-ink'}"
                            onclick={() => (scale = opt.v)}
                        >
                            {opt.label}
                        </button>
                    {/each}
                </div>

                <!-- Category chips -->
                <div class="flex flex-wrap gap-1.5">
                    {#each CATEGORY_CHIPS as chip (chip.key)}
                        <button
                            type="button"
                            class="rounded-full px-3 py-1 text-xs font-semibold transition cursor-pointer border {categoryFilter === chip.key
                                ? 'border-accent/50 bg-accent/15 text-accent-soft'
                                : 'border-white/10 bg-field text-muted hover:text-ink hover:border-white/20'}"
                            onclick={() => (categoryFilter = chip.key)}
                        >
                            {chip.label()}
                        </button>
                    {/each}
                </div>

                <!-- In-progress toggle -->
                <label class="flex cursor-pointer items-center gap-2 text-xs text-muted select-none">
                    <input
                        type="checkbox"
                        bind:checked={includeInProgress}
                        class="h-3.5 w-3.5 rounded accent-accent cursor-pointer"
                    />
                    {i18n.t.views.includeInProgress}
                </label>
            </div>

            <!-- Year anchors (shown when > 1 year) -->
            {#if chronicle.years.length > 1}
                <div class="flex flex-wrap gap-2">
                    {#each chronicle.years as yg (yg.year)}
                        <button
                            type="button"
                            class="rounded-full border border-white/10 bg-field px-3 py-1 text-xs font-bold text-muted tabular-nums transition hover:border-accent/40 hover:text-accent-soft cursor-pointer"
                            onclick={() => scrollToYear(yg.year)}
                        >
                            {yg.year}
                        </button>
                    {/each}
                </div>
            {/if}

            <!-- Empty state -->
            {#if chronicle.years.length === 0 && chronicle.undatedCompleted.length === 0}
                <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-surface p-6 text-center">
                    <div class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted">
                        <CalendarDays size={22} aria-hidden="true" />
                    </div>
                    <p class="text-base font-semibold text-ink">{i18n.t.views.emptyChronicleTitle}</p>
                    <p class="text-sm text-muted">{i18n.t.views.emptyChronicleHint}</p>
                </div>
            {:else}
                <!-- Timeline -->
                <div class="relative border-l-2 border-accent/30 ml-3 sm:ml-4 pl-5 sm:pl-7 space-y-10">
                    {#each chronicle.years as yg (yg.year)}
                        <section id="chronicle-year-{yg.year}">
                            <!-- Year node on timeline -->
                            <div class="absolute -left-[9px] mt-1 h-4 w-4 rounded-full bg-accent ring-4 ring-canvas"></div>

                            <!-- Year heading + stats -->
                            <div class="mb-4 flex flex-wrap items-center gap-3">
                                <h3 class="text-2xl sm:text-3xl font-black tracking-tight text-white tabular-nums">
                                    {yg.year}
                                </h3>
                                <span class="rounded-full bg-field border border-white/10 px-2.5 py-0.5 text-xs font-semibold text-muted">
                                    {i18n.t.views.yearSummaryCount(yg.totalCount)}
                                </span>
                                {#if yg.averageScore !== null}
                                    <span class="rounded-full bg-amber-400/10 border border-amber-400/20 px-2.5 py-0.5 text-xs font-semibold text-amber-300">
                                        {i18n.t.views.yearAvgScore(String(yg.averageScore))}
                                    </span>
                                {/if}
                                {#if yg.topRatedItem}
                                    <button
                                        type="button"
                                        class="inline-flex items-center gap-1.5 rounded-full bg-field border border-white/10 px-2.5 py-0.5 text-xs font-semibold text-muted hover:text-ink transition cursor-pointer truncate max-w-xs"
                                        onclick={() => onOpenMedia?.(yg.topRatedItem!.id)}
                                        title={yg.topRatedItem.title}
                                    >
                                        <Trophy size={11} class="shrink-0 text-amber-400" aria-hidden="true" />
                                        <span class="truncate">{i18n.t.views.yearFavorite(yg.topRatedItem.title)}</span>
                                    </button>
                                {/if}
                            </div>

                            {#if scale === "months"}
                                <!-- ── By-month view ── -->
                                <div class="space-y-8">
                                    {#each yg.months as mg (mg.month)}
                                        <div>
                                            <!-- Month label + dot -->
                                            <div class="relative flex items-center gap-2 mb-3">
                                                <div class="absolute -left-[calc(1.25rem+5px)] sm:-left-[calc(1.75rem+5px)] h-2.5 w-2.5 rounded-full bg-accent/50 ring-2 ring-canvas"></div>
                                                <span class="text-sm font-bold capitalize text-ink/80">
                                                    {monthName(mg.month)}
                                                </span>
                                                <span class="rounded-full bg-field border border-white/10 px-2 py-0.5 text-[10px] font-semibold text-muted tabular-nums">
                                                    {mg.entries.length}
                                                </span>
                                            </div>

                                            <!-- Cards grid -->
                                            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-3.5">
                                                {#each mg.entries as entry (entry.item.id + entry.dateIso)}
                                                    <button
                                                        type="button"
                                                        class="group/card text-left cursor-pointer"
                                                        onclick={() => onOpenMedia?.(entry.item.id)}
                                                        title={entry.item.title}
                                                    >
                                                        <!-- Poster -->
                                                        <div class="relative aspect-[2/3] overflow-hidden rounded-lg bg-canvas">
                                                            {#if entry.item.coverUrl}
                                                                <img
                                                                    src={entry.item.coverUrl}
                                                                    alt={entry.item.title}
                                                                    referrerpolicy="no-referrer"
                                                                    loading="lazy"
                                                                    decoding="async"
                                                                    class="h-full w-full object-cover transition duration-300 group-hover/card:scale-[1.04]"
                                                                />
                                                            {:else}
                                                                <div class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-muted text-xs px-1 text-center">
                                                                    {entry.item.title}
                                                                </div>
                                                            {/if}

                                                            <!-- Badge: score or in-progress -->
                                                            <div class="absolute top-1.5 left-1.5">
                                                                {#if !entry.isCompleted}
                                                                    <span class="rounded bg-blue-500/80 px-1.5 py-0.5 text-[10px] font-bold text-white leading-none">
                                                                        {i18n.t.status.inProgress}
                                                                    </span>
                                                                {:else if entry.item.score && entry.item.score > 0}
                                                                    <span class="rounded bg-black/70 px-1.5 py-0.5 text-[10px] font-bold text-amber-300 leading-none">
                                                                        ★ {entry.item.score}
                                                                    </span>
                                                                {/if}
                                                            </div>
                                                        </div>

                                                        <!-- Card footer -->
                                                        <div class="mt-1.5 px-0.5">
                                                            <p class="text-xs font-semibold text-ink/90 leading-tight line-clamp-2">{entry.item.title}</p>
                                                            <p class="mt-0.5 text-[10px] text-muted flex items-center gap-1 flex-wrap">
                                                                <span>{typeLabel(entry.item)}</span>
                                                                <span aria-hidden="true">·</span>
                                                                <span class="tabular-nums">{shortDate(entry.date)}</span>
                                                            </p>
                                                        </div>
                                                    </button>
                                                {/each}
                                            </div>
                                        </div>
                                    {/each}
                                </div>
                            {:else}
                                <!-- ── By-year mosaic view ── -->
                                <div class="grid grid-cols-3 sm:grid-cols-5 md:grid-cols-7 lg:grid-cols-9 gap-2.5">
                                    {#each yg.entries as entry (entry.item.id + entry.dateIso)}
                                        <button
                                            type="button"
                                            class="group/mini relative aspect-[2/3] overflow-hidden rounded-md bg-canvas cursor-pointer"
                                            onclick={() => onOpenMedia?.(entry.item.id)}
                                            title="{entry.item.title} · {shortDate(entry.date)}{entry.item.score && entry.item.score > 0 ? ` · ★ ${entry.item.score}` : ''}"
                                        >
                                            {#if entry.item.coverUrl}
                                                <img
                                                    src={entry.item.coverUrl}
                                                    alt={entry.item.title}
                                                    referrerpolicy="no-referrer"
                                                    loading="lazy"
                                                    decoding="async"
                                                    class="h-full w-full object-cover transition duration-300 group-hover/mini:scale-[1.06]"
                                                />
                                            {:else}
                                                <div class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-[8px] text-muted text-center px-0.5 leading-tight">
                                                    {entry.item.title}
                                                </div>
                                            {/if}
                                            {#if entry.item.score && entry.item.score > 0}
                                                <span class="absolute bottom-0.5 right-0.5 rounded bg-black/70 px-1 text-[9px] font-bold text-amber-300 leading-tight">
                                                    ★{entry.item.score}
                                                </span>
                                            {/if}
                                        </button>
                                    {/each}
                                </div>
                            {/if}
                        </section>
                    {/each}

                    <!-- Undated completed block -->
                    {#if chronicle.undatedCompleted.length > 0}
                        <section>
                            <div class="absolute -left-[9px] mt-1 h-4 w-4 rounded-full bg-muted/40 ring-4 ring-canvas"></div>
                            <details class="group/details">
                                <summary class="flex cursor-pointer list-none items-center gap-2 text-sm font-semibold text-muted hover:text-ink transition select-none">
                                    <span class="transition group-open/details:rotate-90 inline-block text-xs">▶</span>
                                    {i18n.t.views.undatedCompletedTitle(chronicle.undatedCompleted.length)}
                                </summary>
                                <div class="mt-4 grid grid-cols-3 sm:grid-cols-5 md:grid-cols-7 lg:grid-cols-9 gap-2.5">
                                    {#each chronicle.undatedCompleted as item (item.id)}
                                        <button
                                            type="button"
                                            class="group/mini relative aspect-[2/3] overflow-hidden rounded-md bg-canvas cursor-pointer"
                                            onclick={() => onOpenMedia?.(item.id)}
                                            title="{item.title}{item.score && item.score > 0 ? ` · ★ ${item.score}` : ''}"
                                        >
                                            {#if item.coverUrl}
                                                <img
                                                    src={item.coverUrl}
                                                    alt={item.title}
                                                    referrerpolicy="no-referrer"
                                                    loading="lazy"
                                                    decoding="async"
                                                    class="h-full w-full object-cover transition duration-300 group-hover/mini:scale-[1.06]"
                                                />
                                            {:else}
                                                <div class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-[8px] text-muted text-center px-0.5 leading-tight">
                                                    {item.title}
                                                </div>
                                            {/if}
                                            {#if item.score && item.score > 0}
                                                <span class="absolute bottom-0.5 right-0.5 rounded bg-black/70 px-1 text-[9px] font-bold text-amber-300 leading-tight">
                                                    ★{item.score}
                                                </span>
                                            {/if}
                                        </button>
                                    {/each}
                                </div>
                            </details>
                        </section>
                    {/if}
                </div>
            {/if}
        {/if}

    <!-- ═══════════════════════════════════════════════════════════════════ -->
    <!-- ACTIVITY TAB                                                        -->
    <!-- ═══════════════════════════════════════════════════════════════════ -->
    {:else}
        {#if loadingEvents}
            <div class="space-y-3" aria-hidden="true">
                {#each Array(4) as _, index (index)}
                    <div class="h-16 animate-pulse rounded-lg bg-card"></div>
                {/each}
            </div>
            <p class="sr-only" role="status">{i18n.t.common.loading}</p>
        {:else if loadEventsError}
            <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center">
                <p class="text-sm text-rose-200" role="alert">{errorMessage(loadEventsError)}</p>
                <button
                    type="button"
                    class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                    onclick={retryEvents}
                >
                    <RefreshCw size={15} aria-hidden="true" />
                    {i18n.t.common.retry}
                </button>
            </div>
        {:else if events.length === 0}
            <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-surface p-6 text-center">
                <div class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted">
                    <History size={22} aria-hidden="true" />
                </div>
                <p class="text-sm text-muted">
                    {selectedDate ? i18n.t.views.noActivityForDate : i18n.t.common.noData}
                </p>
            </div>
        {:else}
            <ol class="space-y-3">
                {#each events as event (event.id)}
                    {@const Icon = HISTORY_EVENT_ICONS[event.type] ?? Flag}
                    <li class="group/list flex items-center gap-4 rounded-lg bg-card p-4 transition hover:bg-card/80">
                        <div class="grid h-10 w-10 shrink-0 place-items-center rounded-md bg-accent/15 text-accent-soft">
                            <Icon size={17} aria-hidden="true" />
                        </div>
                        <div class="min-w-0 flex-1">
                            {#if event.title && event.mediaId && event.type !== "Deleted"}
                                <button
                                    type="button"
                                    class="truncate text-sm font-semibold text-ink hover:text-accent-soft hover:underline text-left cursor-pointer transition inline-flex items-center gap-1.5 group/link"
                                    onclick={() => onOpenMedia?.(event.mediaId)}
                                    title={i18n.current === "ru" ? "Перейти к медиа" : "Go to media"}
                                >
                                    <span>{event.title}</span>
                                    <ArrowUpRight size={13} class="opacity-0 group-hover/list:opacity-100 transition text-accent-soft shrink-0" />
                                </button>
                            {:else}
                                <span class="truncate text-sm font-semibold text-muted">
                                    {event.title ?? "—"}
                                </span>
                            {/if}
                            <p class="mt-1 text-xs text-muted">{formatHistoryEventLabel(event)}</p>
                        </div>
                        <div class="flex shrink-0 items-center gap-2">
                            <span class="text-xs text-muted tabular-nums">{formatDate(event.createdAt)}</span>
                            <button
                                type="button"
                                class="grid h-7 w-7 place-items-center rounded-md text-muted opacity-0 transition group-hover/list:opacity-100 hover:bg-rose-500/10 hover:text-rose-400 focus-visible:opacity-100 cursor-pointer disabled:opacity-40"
                                disabled={deletingId !== null}
                                aria-label={i18n.t.views.confirmDeleteHistoryEntry}
                                title={i18n.t.views.confirmDeleteHistoryEntry}
                                onclick={() => void handleDeleteEvent(event)}
                            >
                                {#if deletingId === event.id}
                                    <LoaderCircle size={13} class="animate-spin" aria-hidden="true" />
                                {:else}
                                    <Trash2 size={13} aria-hidden="true" />
                                {/if}
                            </button>
                        </div>
                    </li>
                {/each}
            </ol>
        {/if}
    {/if}
</div>
