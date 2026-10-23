<script lang="ts">
    import { CalendarDays, ChevronLeft, ChevronRight, LayoutGrid, List, Play, RefreshCw, Sparkles } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import { errorMessage, getCalendar, triggerAutoRefresh } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import type { CalendarEventKind, CalendarItemDto, CalendarScheduleDto } from "$shared/types";

    interface Props {
        onOpenMedia?: (mediaId: string) => void;
    }

    let { onOpenMedia }: Props = $props();

    type ViewMode = "feed" | "grid";
    type KindFilter = CalendarEventKind | "all";
    type TypeFilter = string;

    let mode = $state<ViewMode>("feed");
    let viewYear = $state(new Date().getFullYear());
    let viewMonthIndex = $state(new Date().getMonth());
    let calendarRevision = $state(0);
    let selectedDay = $state<string | null>(null);
    let kindFilter = $state<KindFilter>("all");
    let typeFilter = $state<TypeFilter>("all");

    let schedule = $state<CalendarScheduleDto | null>(null);
    let isLoading = $state(false);
    let loadError = $state<unknown>(null);

    const todayStr = localIso(new Date());
    const tomorrowStr = localIso(new Date(Date.now() + 24 * 60 * 60 * 1000));

    // Colours shared by the feed badges and the grid dots, per spec.
    const KIND_CHIP: Record<CalendarEventKind, string> = {
        auto_refresh: "border-indigo-500/30 bg-indigo-500/15 text-indigo-300",
        air_date: "border-emerald-500/30 bg-emerald-500/15 text-emerald-300",
        release: "border-amber-500/30 bg-amber-500/15 text-amber-300",
    };
    const KIND_DOT: Record<CalendarEventKind, string> = {
        auto_refresh: "bg-indigo-400",
        air_date: "bg-emerald-400",
        release: "bg-amber-400",
    };

    function localIso(date: Date): string {
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return `${date.getFullYear()}-${month}-${day}`;
    }

    function isoDate(year: number, monthIndex: number, day: number): string {
        const month = String(monthIndex + 1).padStart(2, "0");
        const padded = String(day).padStart(2, "0");
        return `${year}-${month}-${padded}`;
    }

    $effect(() => {
        const year = viewYear;
        const month = viewMonthIndex;
        const from = isoDate(year, month, 1);
        const to = isoDate(year, month, new Date(year, month + 1, 0).getDate());
        void calendarRevision;
        const requestId = ++fetchRequestId;
        isLoading = true;
        loadError = null;
        getCalendar(from, to)
            .then((result) => {
                if (fetchRequestId !== requestId) return;
                schedule = result;
            })
            .catch((error) => {
                if (fetchRequestId === requestId) loadError = error;
            })
            .finally(() => {
                if (fetchRequestId === requestId) isLoading = false;
            });
    });

    let fetchRequestId = 0;

    function shiftMonth(delta: number) {
        const next = new Date(viewYear, viewMonthIndex + delta, 1);
        viewYear = next.getFullYear();
        viewMonthIndex = next.getMonth();
        selectedDay = null;
    }

    function goToday() {
        const now = new Date();
        viewYear = now.getFullYear();
        viewMonthIndex = now.getMonth();
        selectedDay = null;
    }

    function retry() {
        calendarRevision += 1;
    }

    function openDay(cellDate: string) {
        selectedDay = cellDate;
        mode = "feed";
    }

    async function checkNow(item: CalendarItemDto) {
        if (checkingId) return;
        checkingId = item.mediaId;
        try {
            await triggerAutoRefresh(item.mediaId);
            showToast(i18n.t.detail.autoRefreshDone, "success");
        } catch (error) {
            showToast(errorMessage(error), "error");
        } finally {
            checkingId = null;
            calendarRevision += 1;
        }
    }

    let checkingId = $state<string | null>(null);

    // Filtered view: every consumer (feed, grid dots, empty state) reads this one map.
    const itemsByDate = $derived.by(() => {
        const map = new Map<string, CalendarItemDto[]>();
        for (const day of schedule?.days ?? []) {
            const items = day.items.filter(matchesFilters);
            if (items.length > 0) map.set(day.date, items);
        }
        return map;
    });

    const visibleDays = $derived.by(() => {
        const entries = [...itemsByDate.entries()].sort(([a], [b]) =>
            a.localeCompare(b),
        );
        if (selectedDay) return entries.filter(([date]) => date === selectedDay);
        return entries;
    });

    const gridCells = $derived.by(() => {
        const first = new Date(viewYear, viewMonthIndex, 1);
        const start = new Date(first);
        start.setDate(1 - ((first.getDay() + 6) % 7)); // back to Monday
        const cells: { date: string; dayOfMonth: number; inMonth: boolean }[] = [];
        for (let i = 0; i < 42; i++) {
            const date = new Date(start);
            date.setDate(start.getDate() + i);
            cells.push({
                date: localIso(date),
                dayOfMonth: date.getDate(),
                inMonth: date.getMonth() === viewMonthIndex,
            });
        }
        return cells;
    });

    // 2023-01-02 is a Monday, so +i walks Mon..Sun.
    const weekdays = [0, 1, 2, 3, 4, 5, 6].map((i) =>
        new Intl.DateTimeFormat(i18n.current, { weekday: "narrow" }).format(
            new Date(2023, 0, 2 + i),
        ),
    );

    const monthLabel = $derived.by(() => {
        const raw = new Intl.DateTimeFormat(i18n.current, {
            month: "long",
            year: "numeric",
        }).format(new Date(viewYear, viewMonthIndex, 1));
        return raw.charAt(0).toLocaleUpperCase(i18n.current) + raw.slice(1);
    });

    const isCurrentMonth = $derived(
        viewYear === new Date().getFullYear() && viewMonthIndex === new Date().getMonth(),
    );

    const typeChips = $derived([
        { key: "all", label: i18n.t.views.calendarFilterAll },
        { key: "manga", label: i18n.t.types.manga },
        { key: "anime", label: i18n.t.navigation.anime },
        { key: "tvshow", label: i18n.t.types.tvshow },
        { key: "movie", label: i18n.t.types.movie },
        { key: "game", label: i18n.t.types.game },
        { key: "book", label: i18n.t.types.book },
    ]);

    const kindChips = $derived([
        { key: "all" as KindFilter, label: i18n.t.views.calendarFilterAll },
        { key: "auto_refresh" as KindFilter, label: i18n.t.views.calendarFilterAutoRefresh },
        { key: "air_date" as KindFilter, label: i18n.t.views.calendarFilterAirDate },
        { key: "release" as KindFilter, label: i18n.t.views.calendarFilterRelease },
    ]);

    function matchesFilters(item: CalendarItemDto): boolean {
        if (kindFilter !== "all" && item.kind !== kindFilter) return false;
        if (typeFilter === "all") return true;
        // shortcut: the calendar DTO carries no isAnime flag, so the anime chip
        // falls back to shows as a whole — refine when the server adds the field.
        if (typeFilter === "anime") return item.type === "tvshow";
        return item.type === typeFilter;
    }

    function kindLabel(kind: CalendarEventKind): string {
        switch (kind) {
            case "auto_refresh":
                return i18n.t.views.calendarFilterAutoRefresh;
            case "air_date":
                return i18n.t.views.calendarFilterAirDate;
            case "release":
                return i18n.t.views.calendarFilterRelease;
        }
    }

    function typeLabel(item: CalendarItemDto): string {
        switch (item.type) {
            case "manga":
                return i18n.t.types.manga;
            case "tvshow":
                return i18n.t.types.tvshow;
            case "movie":
                return i18n.t.types.movie;
            case "game":
                return i18n.t.types.game;
            case "book":
                return i18n.t.types.book;
            default:
                return item.type;
        }
    }

    function dayHeading(dateStr: string): string {
        const [year, month, day] = dateStr.split("-").map(Number);
        if (year === undefined || month === undefined || day === undefined) return dateStr;
        return new Intl.DateTimeFormat(i18n.current, {
            weekday: "long",
            day: "numeric",
            month: "long",
        }).format(new Date(year, month - 1, day));
    }

    function progressText(item: CalendarItemDto): string | null {
        if (item.currentProgress === null) return null;
        return `${formatProgress(item.currentProgress)} / ${item.totalCount !== null ? formatProgress(item.totalCount) : "—"}`;
    }

    function formatProgress(value: number): string {
        return new Intl.NumberFormat(i18n.current).format(value);
    }

    function kindCounts(dateStr: string): [CalendarEventKind, number][] {
        const items = itemsByDate.get(dateStr);
        if (!items) return [];
        const counts = new Map<CalendarEventKind, number>();
        for (const item of items) {
            counts.set(item.kind, (counts.get(item.kind) ?? 0) + 1);
        }
        return [...counts.entries()];
    }
</script>

<div class="mx-auto max-w-5xl space-y-5">
    <div>
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">
            {i18n.t.navigation.calendar}
        </p>
        <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">
            {i18n.t.views.calendarTitle}
        </h2>
        <p class="mt-2 text-sm text-muted">{i18n.t.views.calendarSubtitle}</p>
    </div>

    <!-- Month navigation + view toggle -->
    <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-1.5">
            <button
                type="button"
                class="tap grid h-9 w-9 place-items-center rounded-lg border border-white/[0.08] bg-card text-muted transition hover:text-white"
                onclick={() => shiftMonth(-1)}
                title={i18n.t.views.calendarPrevMonth}
                aria-label={i18n.t.views.calendarPrevMonth}
            >
                <ChevronLeft size={17} aria-hidden="true" />
            </button>
            <button
                type="button"
                class="tap h-9 rounded-lg px-3 text-sm font-semibold text-white transition hover:bg-white/5"
                class:opacity-60={isCurrentMonth}
                onclick={goToday}
                title={i18n.t.views.calendarCurrentMonth}
                aria-label={i18n.t.views.calendarCurrentMonth}
            >
                {monthLabel}
            </button>
            <button
                type="button"
                class="tap grid h-9 w-9 place-items-center rounded-lg border border-white/[0.08] bg-card text-muted transition hover:text-white"
                onclick={() => shiftMonth(1)}
                title={i18n.t.views.calendarNextMonth}
                aria-label={i18n.t.views.calendarNextMonth}
            >
                <ChevronRight size={17} aria-hidden="true" />
            </button>
        </div>
        <div class="flex items-center gap-1 rounded-lg border border-white/[0.08] bg-card p-1">
            <button
                type="button"
                class={`tap flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition ${
                    mode === "grid"
                        ? "bg-accent/15 text-accent-soft"
                        : "text-muted hover:text-white"
                }`}
                onclick={() => (mode = "grid")}
            >
                <LayoutGrid size={15} aria-hidden="true" />
                {i18n.t.views.calendarViewMonth}
            </button>
            <button
                type="button"
                class={`tap flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition ${
                    mode === "feed"
                        ? "bg-accent/15 text-accent-soft"
                        : "text-muted hover:text-white"
                }`}
                onclick={() => (mode = "feed")}
            >
                <List size={15} aria-hidden="true" />
                {i18n.t.views.calendarViewFeed}
            </button>
        </div>
    </div>

    <!-- Filters: media types, then event kinds -->
    <div class="flex flex-wrap items-center gap-2">
        {#each typeChips as chip (chip.key)}
            <button
                type="button"
                class={`tap rounded-full border px-3 py-1 text-xs font-semibold transition ${
                    typeFilter === chip.key
                        ? "border-accent/30 bg-accent/15 text-accent-soft"
                        : "border-white/[0.08] bg-card text-muted hover:text-white"
                }`}
                onclick={() => (typeFilter = chip.key)}
            >
                {chip.label}
            </button>
        {/each}
        <span class="mx-1 hidden h-4 w-px bg-white/10 sm:block" aria-hidden="true"></span>
        {#each kindChips as chip (chip.key)}
            <button
                type="button"
                class={`tap rounded-full border px-3 py-1 text-xs font-semibold transition ${
                    kindFilter === chip.key
                        ? chip.key === "all"
                            ? "border-accent/30 bg-accent/15 text-accent-soft"
                            : KIND_CHIP[chip.key]
                        : "border-white/[0.08] bg-card text-muted hover:text-white"
                }`}
                onclick={() => (kindFilter = chip.key)}
            >
                {chip.label}
            </button>
        {/each}
    </div>

    {#if isLoading}
        {#if mode === "feed"}
            <div class="mt-6 space-y-6" aria-hidden="true">
                {#each Array(6) as _, index (index)}
                    <div class="flex items-center gap-3 rounded-xl border border-white/[0.06] bg-card p-2.5 animate-pulse">
                        <div class="aspect-[2/3] w-12 shrink-0 rounded-lg bg-white/5"></div>
                        <div class="w-full space-y-2">
                            <div class="h-3.5 w-1/3 rounded bg-white/5"></div>
                            <div class="h-3 w-1/2 rounded bg-white/5"></div>
                        </div>
                    </div>
                {/each}
            </div>
        {:else}
            <div class="mt-6 grid grid-cols-7 gap-1.5" aria-hidden="true">
                {#each Array(35) as _, index (index)}
                    <div class="min-h-20 rounded-lg bg-card animate-pulse"></div>
                {/each}
            </div>
        {/if}
    {:else if loadError}
        <div class="flex min-h-64 flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-white/10 bg-field/50 p-8 text-center">
            <p class="text-sm text-rose-200" role="alert">{errorMessage(loadError)}</p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover"
                onclick={retry}
            >
                <RefreshCw size={15} aria-hidden="true" />
                {i18n.t.common.retry}
            </button>
        </div>
    {:else if visibleDays.length === 0}
        <div class="flex min-h-[50vh] flex-col items-center justify-center rounded-xl border border-dashed border-white/10 bg-field/50 p-8 text-center sm:p-12">
            <div class="relative grid h-16 w-16 place-items-center rounded-2xl border border-border/60 bg-card shadow-sm">
                <CalendarDays size={28} class="text-accent-soft" aria-hidden="true" />
                <span class="absolute -right-1 -top-1 grid h-5 w-5 place-items-center rounded-full bg-accent text-[10px] text-white">
                    <Sparkles size={11} aria-hidden="true" />
                </span>
            </div>
            <h3 class="mt-6 text-lg font-bold text-ink">
                {i18n.t.views.calendarEmptyTitle}
            </h3>
            <p class="mt-2 max-w-md text-sm leading-relaxed text-muted">
                {i18n.t.views.calendarEmptyHint}
            </p>
        </div>
    {:else if mode === "grid"}
        <div class="grid grid-cols-7 gap-1.5">
            {#each weekdays as weekday, index (index)}
                <div class="text-center text-[11px] font-semibold uppercase tracking-wide text-muted">
                    {weekday}
                </div>
            {/each}
            {#each gridCells as cell (cell.date)}
                {@const counts = kindCounts(cell.date)}
                <button
                    type="button"
                    class={`flex min-h-20 flex-col items-start gap-1 rounded-lg border p-1.5 text-left transition ${
                        cell.date === todayStr
                            ? "border-accent bg-accent/10"
                            : cell.inMonth
                                ? "border-white/[0.06] bg-card hover:border-white/[0.15]"
                                : "border-transparent bg-transparent opacity-40"
                    } ${counts.length > 0 ? "cursor-pointer" : "cursor-default"}`}
                    disabled={counts.length === 0}
                    onclick={() => openDay(cell.date)}
                >
                    <span class={`text-[11px] font-semibold tabular-nums ${cell.inMonth ? "text-ink" : "text-muted"}`}>
                        {cell.dayOfMonth}
                    </span>
                    {#each counts as [kind, count] (kind)}
                        <span class="flex items-center gap-1 text-[10px] text-muted">
                            <span class={`h-1.5 w-1.5 shrink-0 rounded-full ${KIND_DOT[kind]}`} aria-hidden="true"></span>
                            {count}
                            <span class="sr-only">{kindLabel(kind)}</span>
                        </span>
                    {/each}
                </button>
            {/each}
        </div>
    {:else}
        <div class="space-y-6">
            {#if selectedDay}
                <button
                    type="button"
                    class="tap inline-flex items-center gap-1.5 rounded-full border border-accent/30 bg-accent/10 px-3 py-1 text-xs font-semibold text-accent-soft transition hover:bg-accent/20"
                    onclick={() => (selectedDay = null)}
                >
                    {dayHeading(selectedDay)}
                    <span aria-hidden="true">✕</span>
                    <span class="sr-only">{i18n.t.views.calendarAllDays}</span>
                </button>
            {/if}
            {#each visibleDays as [date, items] (date)}
                <section>
                    <header class="mb-2 flex items-center gap-2">
                        <h3 class="text-sm font-bold text-ink">{dayHeading(date)}</h3>
                        {#if date === todayStr}
                            <span class="rounded-full bg-accent px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white ring-2 ring-accent/20">
                                {i18n.t.views.calendarToday}
                            </span>
                        {:else if date === tomorrowStr}
                            <span class="rounded-full border border-accent/30 bg-accent/10 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-accent-soft">
                                {i18n.t.views.calendarTomorrow}
                            </span>
                        {/if}
                    </header>
                    <div class="space-y-2">
                        {#each items as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
                            <div class="group flex items-center gap-3 rounded-xl border border-white/[0.06] bg-card p-2.5 transition hover:border-white/[0.12] hover:bg-field/60">
                                <button
                                    type="button"
                                    class="flex min-w-0 flex-1 items-center gap-3 text-left"
                                    onclick={() => onOpenMedia?.(item.mediaId)}
                                >
                                    <div class="aspect-[2/3] w-12 shrink-0 overflow-hidden rounded-lg bg-white/5">
                                        {#if item.coverUrl}
                                            <img
                                                src={item.coverUrl}
                                                alt={item.title}
                                                loading="lazy"
                                                referrerpolicy="no-referrer"
                                                class="h-full w-full object-cover object-top"
                                            />
                                        {:else}
                                            <div class="grid h-full place-items-center text-muted">
                                                <CalendarDays size={16} aria-hidden="true" />
                                            </div>
                                        {/if}
                                    </div>
                                    <div class="min-w-0 flex-1">
                                        <p class="truncate text-sm font-semibold text-ink">{item.title}</p>
                                        <p class="mt-0.5 truncate text-xs text-muted">
                                            {typeLabel(item)}
                                            {#if item.details}
                                                <span class="text-muted/70">• {item.details}</span>
                                            {/if}
                                        </p>
                                    </div>
                                    <span
                                        class={`hidden shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-semibold sm:inline-flex ${KIND_CHIP[item.kind]}`}
                                    >
                                        {#if item.kind === "auto_refresh"}
                                            <RefreshCw size={12} aria-hidden="true" />
                                        {:else if item.kind === "air_date"}
                                            <Play size={12} aria-hidden="true" />
                                        {:else}
                                            <Sparkles size={12} aria-hidden="true" />
                                        {/if}
                                        {kindLabel(item.kind)}
                                    </span>
                                    {#if progressText(item)}
                                        <span class="hidden shrink-0 font-mono text-[11px] tabular-nums text-muted md:block">
                                            {progressText(item)}
                                        </span>
                                    {/if}
                                </button>
                                {#if item.kind === "auto_refresh"}
                                    <button
                                        type="button"
                                        class="tap flex shrink-0 items-center gap-1.5 rounded-lg border border-indigo-500/30 bg-indigo-500/15 px-2.5 py-1.5 text-[11px] font-semibold text-indigo-300 transition hover:bg-indigo-500/25 disabled:cursor-not-allowed disabled:opacity-70"
                                        disabled={checkingId === item.mediaId}
                                        aria-label={i18n.t.views.calendarCheckNow}
                                        onclick={() => void checkNow(item)}
                                    >
                                        <RefreshCw
                                            size={12}
                                            class={checkingId === item.mediaId ? "animate-spin" : ""}
                                            aria-hidden="true"
                                        />
                                        <span class="hidden sm:inline">
                                            {checkingId === item.mediaId
                                                ? i18n.t.views.calendarChecking
                                                : i18n.t.views.calendarCheckNow}
                                        </span>
                                    </button>
                                {/if}
                            </div>
                        {/each}
                    </div>
                </section>
            {/each}
        </div>
    {/if}
</div>
