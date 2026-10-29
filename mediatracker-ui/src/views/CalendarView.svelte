<script lang="ts">
  import {
    BookOpen,
    CalendarDays,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
    Clapperboard,
    Film,
    Gamepad2,
    Image,
    Layers,
    LayoutGrid,
    Library,
    List,
    Play,
    RefreshCw,
    RotateCcw,
    Sparkles,
    Tv,
  } from "$shared/ui/Icons";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { errorMessage, getCalendar, triggerAutoRefresh } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import MediaCoverPlaceholder from "$shared/ui/MediaCoverPlaceholder.svelte";
  import type {
    CalendarDayDto,
    CalendarEventKind,
    CalendarItemDto,
    CalendarScheduleDto,
  } from "$shared/types";

  interface Props {
    onOpenMedia?: (mediaId: string) => void;
  }

  let { onOpenMedia }: Props = $props();

  type ViewMode = "feed" | "grid";
  type CellMode = "posters" | "icons";
  type KindFilter = "all" | "no_auto_refresh" | "auto_refresh" | "air_date" | "release";
  type TypeFilter = "all" | "manga" | "anime" | "tvshow" | "movie" | "game" | "book";

  let mode = $state<ViewMode>("feed");
  let cellMode = $state<CellMode>(
    typeof localStorage !== "undefined" && localStorage.getItem("calendar_cell_mode") === "icons"
      ? "icons"
      : "posters",
  );
  let viewYear = $state(new Date().getFullYear());
  let viewMonthIndex = $state(new Date().getMonth());
  let calendarRevision = $state(0);
  let selectedDay = $state<string | null>(null);
  let kindFilter = $state<KindFilter>("all");
  let typeFilter = $state<TypeFilter>("all");

  let schedule = $state<CalendarScheduleDto | null>(null);
  let isLoading = $state(false);
  let loadError = $state<unknown>(null);
  let brokenCovers = $state<Set<string>>(new Set());

  // Svelte 5 does not re-render on Set#add mutation, so reassign the set to trigger reactivity.
  function markBroken(url: string) {
    brokenCovers = new Set(brokenCovers).add(url);
  }

  function getTodayIso(): string {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
  }

  function getTomorrowIso(): string {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }

  const todayStr = getTodayIso();
  const tomorrowStr = getTomorrowIso();

  // Colours shared by the feed badges and the grid dots, per spec.
  const KIND_CHIP: Record<CalendarEventKind, string> = {
    auto_refresh: "border-indigo-500/30 bg-indigo-500/15 text-indigo-300",
    air_date: "border-emerald-500/30 bg-emerald-500/15 text-emerald-300",
    release: "border-amber-500/30 bg-amber-500/15 text-amber-300",
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

  function autoSelectGridDay(sched: CalendarScheduleDto, year: number, month: number) {
    if (mode !== "grid") return;
    const monthPrefix = `${year}-${String(month + 1).padStart(2, "0")}`;

    if (selectedDay && selectedDay.startsWith(monthPrefix)) {
      return;
    }

    const todayItems =
      sched.days.find((d) => d.date === todayStr)?.items.filter(matchesFilters) ?? [];
    if (todayStr.startsWith(monthPrefix) && todayItems.length > 0) {
      selectedDay = todayStr;
      return;
    }

    const firstDay = sched.days
      .filter((d) => d.date.startsWith(monthPrefix) && d.items.some(matchesFilters))
      .sort((a, b) => a.date.localeCompare(b.date))[0];

    if (firstDay) {
      selectedDay = firstDay.date;
      return;
    }

    if (todayStr.startsWith(monthPrefix)) {
      selectedDay = todayStr;
    } else {
      selectedDay = isoDate(year, month, 1);
    }
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
        autoSelectGridDay(result, year, month);
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
    selectedDay = getTodayIso();
  }

  function resetFilters() {
    typeFilter = "all";
    kindFilter = "all";
    selectedDay = null;
  }

  function setCellMode(newCellMode: CellMode) {
    cellMode = newCellMode;
    try {
      localStorage.setItem("calendar_cell_mode", newCellMode);
    } catch {}
  }

  function setMode(newMode: ViewMode) {
    mode = newMode;
    if (newMode === "feed") {
      selectedDay = null;
    } else if (newMode === "grid" && schedule) {
      autoSelectGridDay(schedule, viewYear, viewMonthIndex);
    }
  }

  function retry() {
    calendarRevision += 1;
  }

  let checkingIds = $state<Record<string, boolean>>({});

  async function checkNow(item: CalendarItemDto) {
    if (checkingIds[item.mediaId]) return;
    checkingIds[item.mediaId] = true;
    try {
      const updated = await triggerAutoRefresh(item.mediaId);
      showToast(i18n.t.detail.autoRefreshDone, "success");

      if (schedule) {
        const newDays: CalendarDayDto[] = [];
        for (const day of schedule.days) {
          const remaining = day.items.filter(
            (i) => !(i.mediaId === item.mediaId && i.kind === "auto_refresh"),
          );
          if (remaining.length > 0) {
            newDays.push({ ...day, items: remaining });
          }
        }

        if (updated.nextAutoRefreshAt) {
          const nextDateStr = updated.nextAutoRefreshAt.slice(0, 10);
          if (nextDateStr >= schedule.from && nextDateStr <= schedule.to) {
            let curProgress: number | null = item.currentProgress;
            let totCount: number | null = item.totalCount;

            if (updated.type === "manga") {
              curProgress = updated.currentChapter;
              totCount = updated.totalChapters;
            } else if (updated.type === "tvshow") {
              curProgress = updated.totalEpisodesWatched;
              totCount = updated.totalEpisodesCount;
            } else if (updated.type === "book") {
              curProgress = updated.currentPage;
              totCount = updated.totalPages;
            }

            const interval = updated.autoRefreshIntervalDays ?? 7;
            const updatedItem: CalendarItemDto = {
              ...item,
              coverUrl: updated.coverUrl ?? item.coverUrl,
              currentProgress: curProgress,
              totalCount: totCount,
              details: `Проверка обновлений (раз в ${interval} дн.)`,
            };

            const dayIndex = newDays.findIndex((d) => d.date === nextDateStr);
            if (dayIndex >= 0) {
              const existingDay = newDays[dayIndex];
              newDays[dayIndex] = {
                ...existingDay,
                items: [...existingDay.items, updatedItem].sort(
                  (a, b) =>
                    a.kind.localeCompare(b.kind) ||
                    (a.details ?? "").localeCompare(b.details ?? ""),
                ),
              };
            } else {
              newDays.push({
                date: nextDateStr,
                items: [updatedItem],
              });
              newDays.sort((a, b) => a.date.localeCompare(b.date));
            }
          }
        }

        schedule = {
          ...schedule,
          days: newDays,
        };
      }
    } catch (error) {
      showToast(errorMessage(error), "error");
    } finally {
      const next = { ...checkingIds };
      delete next[item.mediaId];
      checkingIds = next;
    }
  }

  const handleCheckNow = checkNow;

  // Filtered view: every consumer (feed, grid, empty state) reads this one map.
  const itemsByDate = $derived.by(() => {
    const map = new Map<string, CalendarItemDto[]>();
    for (const day of schedule?.days ?? []) {
      const items = day.items.filter(matchesFilters);
      if (items.length > 0) map.set(day.date, items);
    }
    return map;
  });

  const visibleDays = $derived.by(() => {
    const entries = [...itemsByDate.entries()].sort(([a], [b]) => a.localeCompare(b));
    if (selectedDay) return entries.filter(([date]) => date === selectedDay);
    return entries;
  });

  const hasActiveFilters = $derived(
    typeFilter !== "all" || kindFilter !== "all" || selectedDay !== null,
  );

  const gridCells = $derived.by(() => {
    const first = new Date(viewYear, viewMonthIndex, 1);
    const start = new Date(first);
    start.setDate(1 - ((first.getDay() + 6) % 7)); // back to Monday

    const lastOfMonth = new Date(viewYear, viewMonthIndex + 1, 0);
    const lastDayMondayZero = (lastOfMonth.getDay() + 6) % 7;
    const daysToSunday = 6 - lastDayMondayZero;
    const end = new Date(lastOfMonth);
    end.setDate(lastOfMonth.getDate() + daysToSunday);

    const totalDays = Math.round((end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000)) + 1;
    const cells: { date: string; dayOfMonth: number; inMonth: boolean }[] = [];
    for (let i = 0; i < totalDays; i++) {
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
  const weekdays = [0, 1, 2, 3, 4, 5, 6].map((i) => {
    const raw = new Intl.DateTimeFormat(i18n.current, { weekday: "short" }).format(
      new Date(2023, 0, 2 + i),
    );
    return raw.charAt(0).toUpperCase() + raw.slice(1);
  });

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

  const categoryOptions = $derived([
    { value: "all" as TypeFilter, label: i18n.t.views.calendarFilterAllCategories },
    { value: "manga" as TypeFilter, label: i18n.t.types.manga },
    { value: "anime" as TypeFilter, label: i18n.t.navigation.anime },
    { value: "tvshow" as TypeFilter, label: i18n.t.types.tvshow },
    { value: "movie" as TypeFilter, label: i18n.t.types.movie },
    { value: "game" as TypeFilter, label: i18n.t.types.game },
    { value: "book" as TypeFilter, label: i18n.t.types.book },
  ]);

  const eventKindOptions = $derived([
    { value: "all" as KindFilter, label: i18n.t.views.calendarFilterAllEvents },
    { value: "no_auto_refresh" as KindFilter, label: i18n.t.views.calendarFilterNoAutoRefresh },
    { value: "auto_refresh" as KindFilter, label: i18n.t.views.calendarFilterOnlyAutoRefresh },
    { value: "air_date" as KindFilter, label: i18n.t.views.calendarFilterOnlyAirDate },
    { value: "release" as KindFilter, label: i18n.t.views.calendarFilterOnlyRelease },
  ]);

  function matchesFilters(item: CalendarItemDto): boolean {
    if (kindFilter === "no_auto_refresh") {
      if (item.kind === "auto_refresh") return false;
    } else if (kindFilter !== "all") {
      if (item.kind !== kindFilter) return false;
    }

    if (typeFilter === "all") return true;
    if (typeFilter === "anime") {
      return item.isAnime === true || item.type === "anime";
    }
    if (typeFilter === "tvshow") {
      return item.type === "tvshow" && !item.isAnime;
    }
    if (typeFilter === "movie") {
      return item.type === "movie" && !item.isAnime;
    }
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
    if (item.isAnime || item.type === "anime") {
      return i18n.t.navigation.anime;
    }
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

  function formatProgress(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value);
  }

  function formatItemProgress(item: CalendarItemDto): string | null {
    if (item.currentProgress === null) return null;
    const cur = formatProgress(item.currentProgress);
    const unit =
      item.type === "manga"
        ? i18n.current === "ru"
          ? "гл."
          : "ch."
        : item.type === "tvshow" || item.isAnime
          ? i18n.current === "ru"
            ? "сер."
            : "ep."
          : item.type === "book"
            ? i18n.current === "ru"
              ? "стр."
              : "p."
            : "";

    if (item.totalCount !== null && item.totalCount > 0) {
      if (item.currentProgress > item.totalCount) {
        return unit ? `${cur} ${unit}` : cur;
      }
      const tot = formatProgress(item.totalCount);
      return unit ? `${cur} / ${tot} ${unit}` : `${cur} / ${tot}`;
    }

    if (item.totalCount === null || item.totalCount === 0) {
      return unit ? `${cur} / — ${unit}` : `${cur} / —`;
    }

    return unit ? `${cur} ${unit}` : cur;
  }

  function formatEventsCount(count: number): string {
    if (i18n.current === "ru") {
      const mod10 = count % 10;
      const mod100 = count % 100;
      if (mod100 >= 11 && mod100 <= 19) return `${count} событий`;
      if (mod10 === 1) return `${count} событие`;
      if (mod10 >= 2 && mod10 <= 4) return `${count} события`;
      return `${count} событий`;
    }
    return count === 1 ? "1 event" : `${count} events`;
  }

  function getItemIconSpec(item: CalendarItemDto) {
    if (item.isAnime || item.type === "anime") {
      return {
        icon: Clapperboard,
        classes: "bg-purple-500/15 text-purple-300 border-purple-500/30",
      };
    }
    switch (item.type) {
      case "manga":
        return {
          icon: Library,
          classes: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
        };
      case "tvshow":
        return {
          icon: Tv,
          classes: "bg-sky-500/15 text-sky-300 border-sky-500/30",
        };
      case "movie":
        return {
          icon: Film,
          classes: "bg-amber-500/15 text-amber-300 border-amber-500/30",
        };
      case "game":
        return {
          icon: Gamepad2,
          classes: "bg-indigo-500/15 text-indigo-300 border-indigo-500/30",
        };
      case "book":
        return {
          icon: BookOpen,
          classes: "bg-rose-500/15 text-rose-300 border-rose-500/30",
        };
      default:
        return {
          icon: Sparkles,
          classes: "bg-slate-500/15 text-slate-300 border-slate-500/30",
        };
    }
  }

  function formatTypeAndProgress(item: CalendarItemDto): string {
    const label = typeLabel(item);
    const progress = formatItemProgress(item);
    return progress ? `${label} · ${progress}` : label;
  }

  function formatEventShortLabel(item: CalendarItemDto): string {
    if (item.kind === "release") {
      return i18n.current === "ru" ? "Релиз" : "Release";
    }
    if (item.kind === "air_date") {
      return (
        item.details ||
        (item.seasonNumber && item.episodeNumber
          ? `S${item.seasonNumber} E${item.episodeNumber}`
          : i18n.current === "ru"
            ? "Серия"
            : "Ep.")
      );
    }
    const match = item.details?.match(/\d+/);
    const days = match ? match[0] : "7";
    return i18n.current === "ru" ? `раз в ${days} дн.` : `every ${days} d.`;
  }

  function groupDayItems(items: CalendarItemDto[]) {
    const releases: CalendarItemDto[] = [];
    const airDates: CalendarItemDto[] = [];
    const autoRefreshMap = new Map<
      string,
      { label: string; daysNum: number; items: CalendarItemDto[] }
    >();

    for (const item of items) {
      if (item.kind === "release") {
        releases.push(item);
      } else if (item.kind === "air_date") {
        airDates.push(item);
      } else if (item.kind === "auto_refresh") {
        const match = item.details?.match(/\d+/);
        const daysNum = match ? parseInt(match[0], 10) : 7;
        const key = `interval_${daysNum}`;
        const label =
          i18n.current === "ru"
            ? `Проверка обновлений · раз в ${daysNum} дн.`
            : `Update checks · every ${daysNum} d.`;

        let group = autoRefreshMap.get(key);
        if (!group) {
          group = { label, daysNum, items: [] };
          autoRefreshMap.set(key, group);
        }
        group.items.push(item);
      }
    }

    const autoRefreshGroups = [...autoRefreshMap.values()].sort((a, b) => a.daysNum - b.daysNum);

    return { releases, airDates, autoRefreshGroups };
  }
</script>

{#snippet renderItemTooltip(item: CalendarItemDto)}
  <div
    class="pointer-events-none invisible absolute bottom-full left-1/2 z-50 mb-2 w-56 -translate-x-1/2 rounded-xl border border-white/10 bg-[#181b24] p-2.5 text-left opacity-0 shadow-2xl shadow-black/80 transition-transform duration-150 group-hover/item:visible group-hover/item:opacity-100"
  >
    {#if item.kind === "auto_refresh"}
      <span
        class="inline-flex items-center gap-1 rounded-full border border-indigo-500/30 bg-indigo-500/15 px-2 py-0.5 text-[10px] font-semibold text-indigo-300"
      >
        <span>🔄</span>
        <span>{i18n.current === "ru" ? "Автообновление" : "Auto-check"}</span>
      </span>
    {:else if item.kind === "air_date"}
      <span
        class="inline-flex items-center gap-1 rounded-full border border-emerald-500/30 bg-emerald-500/15 px-2 py-0.5 text-[10px] font-semibold text-emerald-300"
      >
        <span>🎬</span>
        <span>{i18n.current === "ru" ? "Выход серии" : "Episode"}</span>
      </span>
    {:else}
      <span
        class="inline-flex items-center gap-1 rounded-full border border-amber-500/30 bg-amber-500/15 px-2 py-0.5 text-[10px] font-semibold text-amber-300"
      >
        <span>🚀</span>
        <span>{i18n.current === "ru" ? "Релиз" : "Release"}</span>
      </span>
    {/if}
    <p class="mt-1 line-clamp-2 text-xs leading-snug font-bold text-white">{item.title}</p>
    <p class="mt-0.5 text-[11px] text-slate-400">
      {typeLabel(item)}
      {#if formatItemProgress(item)}
        · {formatItemProgress(item)}
      {/if}
      {#if item.details}
        · {item.details}
      {/if}
    </p>
  </div>
{/snippet}

{#snippet renderItemCard(item: CalendarItemDto, compact = false, hideDetails = false)}
  <div
    class={`group bg-card hover:bg-field/60 flex items-center gap-3 rounded-xl border border-white/[0.06] transition hover:border-white/[0.12] ${
      compact ? "p-2.5" : "p-3"
    }`}
  >
    <button
      type="button"
      class={`flex min-w-0 flex-1 items-center text-left ${compact ? "gap-2.5" : "gap-3 sm:gap-4"}`}
      onclick={() => onOpenMedia?.(item.mediaId)}
    >
      <div
        class={`aspect-[2/3] shrink-0 overflow-hidden rounded-lg bg-white/5 shadow-md ring-1 ring-white/10 ${
          compact ? "w-12 sm:w-14" : "w-16 sm:w-20"
        }`}
      >
        {#if item.coverUrl && !brokenCovers.has(item.coverUrl)}
          <img
            src={item.coverUrl}
            alt={item.title}
            loading="lazy"
            referrerpolicy="no-referrer"
            class="h-full w-full object-cover object-top"
            onerror={(e) => {
              const target = e.currentTarget as HTMLImageElement;
              markBroken(item.coverUrl!);
              target.src = "";
            }}
          />
        {:else}
          <MediaCoverPlaceholder
            class={`h-full w-full object-cover object-top ${compact ? "size-12 sm:size-14" : "size-16 sm:size-20"}`}
          />
        {/if}
      </div>
      <div class="min-w-0 flex-1">
        {#if compact}
          <p class="text-ink line-clamp-2 text-sm leading-snug font-semibold">{item.title}</p>
          <p class="mt-1 truncate text-xs font-medium text-slate-300">
            {typeLabel(item)}
            {#if formatItemProgress(item)}
              <span class="text-muted/50"> · </span><span class="font-mono tabular-nums"
                >{formatItemProgress(item)}</span
              >
            {/if}
          </p>
          {#if item.details && !hideDetails}
            <p class="text-muted mt-0.5 truncate text-[11px]">{item.details}</p>
          {/if}
        {:else}
          <p class="text-ink truncate text-sm font-semibold sm:text-base">{item.title}</p>
          <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs">
            <span class="font-medium text-slate-300">
              {typeLabel(item)}{#if formatItemProgress(item)}<span class="text-muted/50">
                  ·
                </span><span class="font-mono tabular-nums">{formatItemProgress(item)}</span>{/if}
            </span>
            {#if item.details && !hideDetails}
              <span class="text-muted/80">
                <span class="text-muted/50 mr-2">·</span>{item.details}
              </span>
            {/if}
          </div>
        {/if}
      </div>
    </button>
    <div class="flex shrink-0 items-center gap-2">
      {#if item.kind !== "auto_refresh"}
        <span
          class={`inline-flex shrink-0 items-center justify-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-semibold ${KIND_CHIP[item.kind]}`}
        >
          {#if item.kind === "air_date"}
            <Play size={12} aria-hidden="true" />
          {:else}
            <Sparkles size={12} aria-hidden="true" />
          {/if}
          {kindLabel(item.kind)}
        </span>
      {/if}
      {#if item.kind === "auto_refresh"}
        <button
          type="button"
          class="tap grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg border border-indigo-500/30 bg-indigo-500/15 text-indigo-300 transition hover:bg-indigo-500/25 hover:text-white disabled:cursor-not-allowed disabled:opacity-50 sm:size-9"
          disabled={Boolean(checkingIds[item.mediaId])}
          title={checkingIds[item.mediaId]
            ? i18n.t.views.calendarChecking
            : i18n.t.views.calendarCheckUpdatesTooltip}
          aria-label={i18n.t.views.calendarCheckNow}
          onclick={(e) => {
            e.stopPropagation();
            void handleCheckNow(item);
          }}
        >
          <RefreshCw
            size={15}
            class={checkingIds[item.mediaId] ? "animate-spin" : ""}
            aria-hidden="true"
          />
        </button>
      {/if}
    </div>
  </div>
{/snippet}

{#snippet renderFeedCard(item: CalendarItemDto)}
  <div
    role="button"
    tabindex="0"
    class="group bg-card hover:bg-card-hover relative flex cursor-pointer flex-col rounded-xl border border-white/[0.05] p-2.5 text-left shadow-lg transition hover:border-white/[0.12]"
    onclick={() => onOpenMedia?.(item.mediaId)}
    onkeydown={(e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        onOpenMedia?.(item.mediaId);
      }
    }}
  >
    <!-- Poster -->
    <div class="bg-canvas relative aspect-[3/4] overflow-hidden rounded-lg">
      {#if item.coverUrl && !brokenCovers.has(item.coverUrl)}
        <img
          src={item.coverUrl}
          alt={item.title}
          loading="lazy"
          referrerpolicy="no-referrer"
          class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
          onerror={(e) => {
            const target = e.currentTarget as HTMLImageElement;
            markBroken(item.coverUrl!);
            target.src = "";
          }}
        />
      {:else}
        <MediaCoverPlaceholder
          class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
        />
      {/if}

      <!-- Refresh button top-right (for auto_refresh) -->
      {#if item.kind === "auto_refresh"}
        <button
          type="button"
          class="tap hover:border-accent hover:bg-accent absolute top-2 right-2 z-10 grid size-7 cursor-pointer place-items-center rounded-lg border border-white/15 bg-[#0d0f14]/85 text-indigo-300 shadow-md backdrop-blur-md transition hover:text-white disabled:cursor-not-allowed disabled:opacity-50 sm:size-8"
          disabled={Boolean(checkingIds[item.mediaId])}
          title={checkingIds[item.mediaId]
            ? i18n.t.views.calendarChecking
            : i18n.t.views.calendarCheckUpdatesTooltip}
          aria-label={i18n.t.views.calendarCheckNow}
          onclick={(e) => {
            e.stopPropagation();
            void handleCheckNow(item);
          }}
        >
          <RefreshCw
            size={14}
            class={checkingIds[item.mediaId] ? "animate-spin" : ""}
            aria-hidden="true"
          />
        </button>
      {/if}
    </div>

    <!-- Details block under poster -->
    <div class="flex min-w-0 flex-1 flex-col justify-between px-0.5 pt-2.5">
      <div class="min-w-0">
        <p class="text-ink truncate text-sm font-semibold" title={item.title}>
          {item.title}
        </p>
        <p class="text-muted mt-0.5 truncate text-xs">
          {formatTypeAndProgress(item)}
        </p>
      </div>

      <div
        class="bg-canvas mt-2 flex items-center justify-between gap-2 rounded-md px-2.5 py-1.5 text-xs"
      >
        <span class="text-muted">
          {item.kind === "auto_refresh"
            ? i18n.current === "ru"
              ? "Проверка"
              : "Check"
            : item.kind === "air_date"
              ? i18n.current === "ru"
                ? "Эпизод"
                : "Episode"
              : i18n.current === "ru"
                ? "Событие"
                : "Event"}
        </span>
        <span
          class="font-semibold tabular-nums {item.kind === 'auto_refresh'
            ? 'text-indigo-300'
            : item.kind === 'air_date'
              ? 'text-emerald-300'
              : 'text-amber-300'}"
        >
          {formatEventShortLabel(item)}
        </span>
      </div>
    </div>
  </div>
{/snippet}

<div class="w-full space-y-6">
  <!-- Compact control panel (Month navigation, filters, reset, view modes) -->
  <div class="flex flex-wrap items-center justify-between gap-3">
    <!-- Left: Month navigation + Filters + Reset -->
    <div class="flex flex-wrap items-center gap-2 sm:gap-2.5">
      <div class="flex items-center gap-1.5">
        <button
          type="button"
          class="tap bg-card text-muted grid h-9 w-9 place-items-center rounded-lg border border-white/[0.08] transition hover:text-white"
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
          class="tap bg-card text-muted grid h-9 w-9 place-items-center rounded-lg border border-white/[0.08] transition hover:text-white"
          onclick={() => shiftMonth(1)}
          title={i18n.t.views.calendarNextMonth}
          aria-label={i18n.t.views.calendarNextMonth}
        >
          <ChevronRight size={17} aria-hidden="true" />
        </button>
      </div>

      <PopoverMenu
        id="calendar-category"
        options={categoryOptions}
        selected={typeFilter}
        onSelect={(val) => (typeFilter = val as TypeFilter)}
        label={i18n.t.views.calendarCategoryLabel}
        placement="bottom-start"
        openOnHover
        closeDelay={200}
      >
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            class="tap bg-field text-ink flex h-9 shrink-0 items-center gap-2 rounded-lg border border-white/10 px-3 text-xs font-semibold transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
          >
            <span class="truncate"
              >{categoryOptions.find((o) => o.value === typeFilter)?.label ??
                i18n.t.views.calendarFilterAllCategories}</span
            >
            <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
          </button>
        {/snippet}
      </PopoverMenu>

      <PopoverMenu
        id="calendar-kind"
        options={eventKindOptions}
        selected={kindFilter}
        onSelect={(val) => (kindFilter = val as KindFilter)}
        label={i18n.t.views.calendarEventKindLabel}
        placement="bottom-start"
        openOnHover
        closeDelay={200}
      >
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            class="tap bg-field text-ink flex h-9 shrink-0 items-center gap-2 rounded-lg border border-white/10 px-3 text-xs font-semibold transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
          >
            <span class="truncate"
              >{eventKindOptions.find((o) => o.value === kindFilter)?.label ??
                i18n.t.views.calendarFilterAllEvents}</span
            >
            <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
          </button>
        {/snippet}
      </PopoverMenu>

      {#if hasActiveFilters}
        <button
          type="button"
          class="tap bg-field text-muted inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg border border-white/10 px-3 text-xs font-semibold transition hover:border-white/20 hover:text-white"
          onclick={resetFilters}
          title={i18n.t.views.calendarReset}
        >
          <RotateCcw size={13} aria-hidden="true" />
          <span>{i18n.t.views.calendarReset}</span>
        </button>
      {/if}
    </div>

    <!-- Right: Cell Mode Switcher (Posters / Icons) + View Mode Switcher (Grid / Feed) -->
    <div class="flex flex-wrap items-center gap-2">
      {#if mode === "grid"}
        <div class="bg-card flex items-center gap-1 rounded-lg border border-white/[0.08] p-1">
          <button
            type="button"
            class={`tap flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition ${
              cellMode === "posters"
                ? "bg-accent/15 text-accent-soft"
                : "text-muted hover:text-white"
            }`}
            onclick={() => setCellMode("posters")}
            title={i18n.t.views.calendarCellModePosters}
          >
            <Image size={15} aria-hidden="true" />
            <span class="hidden sm:inline">{i18n.t.views.calendarCellModePosters}</span>
          </button>
          <button
            type="button"
            class={`tap flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition ${
              cellMode === "icons" ? "bg-accent/15 text-accent-soft" : "text-muted hover:text-white"
            }`}
            onclick={() => setCellMode("icons")}
            title={i18n.t.views.calendarCellModeIcons}
          >
            <Layers size={15} aria-hidden="true" />
            <span class="hidden sm:inline">{i18n.t.views.calendarCellModeIcons}</span>
          </button>
        </div>
      {/if}

      <div class="bg-card flex items-center gap-1 rounded-lg border border-white/[0.08] p-1">
        <button
          type="button"
          class={`tap flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition ${
            mode === "grid" ? "bg-accent/15 text-accent-soft" : "text-muted hover:text-white"
          }`}
          onclick={() => setMode("grid")}
        >
          <LayoutGrid size={15} aria-hidden="true" />
          {i18n.t.views.calendarViewMonth}
        </button>
        <button
          type="button"
          class={`tap flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition ${
            mode === "feed" ? "bg-accent/15 text-accent-soft" : "text-muted hover:text-white"
          }`}
          onclick={() => setMode("feed")}
        >
          <List size={15} aria-hidden="true" />
          {i18n.t.views.calendarViewFeed}
        </button>
      </div>
    </div>
  </div>

  {#if isLoading}
    {#if mode === "feed"}
      <div class="mt-6 space-y-6" aria-hidden="true">
        <div class="h-5 w-40 animate-pulse rounded bg-white/5"></div>
        <div
          class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7"
        >
          {#each Array(7) as _, index (index)}
            <div
              class="bg-card flex animate-pulse flex-col space-y-2.5 rounded-xl border border-white/[0.05] p-2.5"
            >
              <div class="aspect-[3/4] w-full rounded-lg bg-white/5"></div>
              <div class="space-y-1.5 px-0.5">
                <div class="h-4 w-3/4 rounded bg-white/5"></div>
                <div class="h-3 w-1/2 rounded bg-white/5"></div>
              </div>
              <div class="h-7 w-full rounded-md bg-white/5"></div>
            </div>
          {/each}
        </div>
      </div>
    {:else}
      <div
        class="mt-6 grid grid-cols-1 items-start gap-6 lg:grid-cols-[1fr_400px] xl:grid-cols-[1fr_440px]"
        aria-hidden="true"
      >
        <div class="grid grid-cols-7 gap-1.5">
          {#each Array(35) as _, index (index)}
            <div class="bg-card min-h-28 animate-pulse rounded-lg sm:min-h-32"></div>
          {/each}
        </div>
        <div class="bg-surface h-64 animate-pulse rounded-xl border border-white/[0.07] p-4"></div>
      </div>
    {/if}
  {:else if loadError}
    <div
      class="bg-field/50 flex min-h-64 flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-white/10 p-8 text-center"
    >
      <p class="text-sm text-rose-200" role="alert">{errorMessage(loadError)}</p>
      <button
        type="button"
        class="bg-accent hover:bg-accent-hover inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium text-white transition"
        onclick={retry}
      >
        <RefreshCw size={15} aria-hidden="true" />
        {i18n.t.common.retry}
      </button>
    </div>
  {:else if mode === "feed" && visibleDays.length === 0}
    <div
      class="bg-field/50 flex min-h-[50vh] flex-col items-center justify-center rounded-xl border border-dashed border-white/10 p-8 text-center sm:p-12"
    >
      <div
        class="border-border/60 bg-card relative grid h-16 w-16 place-items-center rounded-2xl border shadow-sm"
      >
        <CalendarDays size={28} class="text-accent-soft" aria-hidden="true" />
        <span
          class="bg-accent absolute -top-1 -right-1 grid h-5 w-5 place-items-center rounded-full text-[10px] text-white"
        >
          <Sparkles size={11} aria-hidden="true" />
        </span>
      </div>
      <h3 class="text-ink mt-6 text-lg font-bold">
        {i18n.t.views.calendarEmptyTitle}
      </h3>
      <p class="text-muted mt-2 max-w-md text-sm leading-relaxed">
        {i18n.t.views.calendarEmptyHint}
      </p>
    </div>
  {:else if mode === "grid"}
    {@const selectedItems = selectedDay ? (itemsByDate.get(selectedDay) ?? []) : []}
    <div
      class="grid grid-cols-1 items-start gap-6 lg:grid-cols-[1fr_400px] xl:grid-cols-[1fr_440px]"
    >
      <!-- Left column: Month Grid -->
      <div class="min-w-0 space-y-1.5">
        <div class="grid grid-cols-7 gap-1.5">
          {#each weekdays as weekday, index (index)}
            <div
              class="py-2 text-center text-xs font-bold tracking-wider text-[#94A3B8] uppercase sm:text-[13px]"
            >
              {weekday}
            </div>
          {/each}
          {#each gridCells as cell (cell.date)}
            {@const cellItems = itemsByDate.get(cell.date) ?? []}
            {@const isSelected = selectedDay === cell.date}
            {@const isToday = cell.date === todayStr}
            {#if !cell.inMonth}
              <div
                class="pointer-events-none relative flex min-h-28 flex-col rounded-xl border border-white/[0.03] bg-[#12151c]/20 p-2 text-left opacity-45 sm:min-h-32"
              >
                <span
                  class="text-muted/60 absolute top-2 left-2.5 px-0.5 text-[11px] font-semibold tabular-nums"
                >
                  {cell.dayOfMonth}
                </span>
              </div>
            {:else}
              <!-- svelte-ignore a11y_click_events_have_key_events -->
              <!-- svelte-ignore a11y_no_static_element_interactions -->
              <div
                class={`relative flex min-h-28 cursor-pointer items-center justify-center rounded-xl border p-2 text-left transition hover:z-20 sm:min-h-32 ${
                  isSelected
                    ? "border-accent/40 ring-accent bg-accent/[0.04] ring-2"
                    : cellItems.length > 0
                      ? "border-white/[0.08] bg-white/[0.03] hover:border-white/[0.16]"
                      : "border-white/[0.04] bg-[#12151c]/40 hover:border-white/[0.08]"
                }`}
                onclick={() => {
                  selectedDay = cell.date;
                }}
              >
                <div
                  class="pointer-events-none absolute inset-x-2.5 top-2 z-10 flex items-center justify-between"
                >
                  <button
                    type="button"
                    class="tap pointer-events-auto -m-1 rounded-md p-1 transition hover:bg-white/10"
                    onclick={(e) => {
                      e.stopPropagation();
                      selectedDay = cell.date;
                    }}
                    title={dayHeading(cell.date)}
                  >
                    {#if isToday}
                      <span
                        class="bg-accent grid h-5 w-5 place-items-center rounded-full text-[11px] font-bold text-white tabular-nums"
                      >
                        {cell.dayOfMonth}
                      </span>
                    {:else}
                      <span
                        class={`px-0.5 text-[11px] font-semibold tabular-nums ${isSelected ? "text-accent-soft" : "text-ink"}`}
                      >
                        {cell.dayOfMonth}
                      </span>
                    {/if}
                  </button>
                  {#if cellItems.length > 3}
                    <span
                      class="bg-accent/15 text-accent-soft ring-accent/30 pointer-events-auto rounded-full px-1.5 py-0.5 text-[10px] font-bold tabular-nums ring-1"
                    >
                      +{cellItems.length - 3}
                    </span>
                  {/if}
                </div>

                {#if cellItems.length > 0}
                  {#if cellMode === "icons"}
                    <div class="flex w-full flex-wrap items-center justify-center gap-1.5 px-1">
                      {#each cellItems.slice(0, 3) as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
                        {@const spec = getItemIconSpec(item)}
                        {@const IconComp = spec.icon}
                        <div
                          class="group/item relative shrink-0 transition duration-200 ease-out hover:z-30"
                        >
                          <div
                            class={`grid size-8 place-items-center rounded-lg border shadow-sm transition-transform duration-150 hover:scale-[1.03] hover:shadow-md ${spec.classes}`}
                          >
                            <IconComp size={16} aria-hidden="true" />
                          </div>
                          {@render renderItemTooltip(item)}
                        </div>
                      {/each}
                    </div>
                  {:else}
                    <div
                      class="flex w-full items-center justify-center -space-x-3.5 px-1 sm:-space-x-4"
                    >
                      {#each cellItems.slice(0, 3) as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
                        <div
                          class="group/item relative shrink-0 transition duration-200 ease-out hover:z-30"
                        >
                          <div
                            class="hover:ring-accent aspect-[2/3] h-14 w-10 overflow-hidden rounded-lg bg-white/5 object-cover shadow-md ring-1 ring-white/15 transition-transform duration-200 ease-out hover:-translate-y-1 hover:scale-[1.03] hover:shadow-xl hover:ring-2 sm:h-16 sm:w-11"
                          >
                            {#if item.coverUrl && !brokenCovers.has(item.coverUrl)}
                              <img
                                src={item.coverUrl}
                                alt={item.title}
                                loading="lazy"
                                referrerpolicy="no-referrer"
                                class="h-full w-full object-cover object-top"
                                onerror={(e) => {
                                  const target = e.currentTarget as HTMLImageElement;
                                  markBroken(item.coverUrl!);
                                  target.src = "";
                                }}
                              />
                            {:else}
                              <MediaCoverPlaceholder
                                class="h-full w-full object-cover object-top"
                              />
                            {/if}
                          </div>
                          {@render renderItemTooltip(item)}
                        </div>
                      {/each}
                    </div>
                  {/if}
                {/if}
              </div>
            {/if}
          {/each}
        </div>
      </div>

      <!-- Right column: Selected Day Panel -->
      <aside
        class="bg-surface min-w-0 space-y-3 rounded-xl border border-white/[0.07] p-4 lg:sticky lg:top-4"
      >
        {#if selectedDay}
          <div class="flex items-center justify-between gap-2 border-b border-white/[0.06] pb-3">
            <div class="min-w-0 flex-1">
              <h3 class="text-ink truncate text-sm font-bold capitalize">
                {dayHeading(selectedDay)}
              </h3>
              <p class="text-muted mt-0.5 text-xs">
                {#if selectedItems.length === 0}
                  {i18n.current === "ru" ? "Нет событий" : "No events"}
                {:else}
                  {formatEventsCount(selectedItems.length)}
                {/if}
              </p>
            </div>
            {#if selectedDay === todayStr}
              <span
                class="bg-accent shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold tracking-wide text-white uppercase"
              >
                {i18n.t.views.calendarToday}
              </span>
            {:else if selectedDay === tomorrowStr}
              <span
                class="border-accent/30 bg-accent/10 text-accent-soft shrink-0 rounded-full border px-2 py-0.5 text-[10px] font-bold tracking-wide uppercase"
              >
                {i18n.t.views.calendarTomorrow}
              </span>
            {/if}
          </div>

          {#if selectedItems.length === 0}
            <div class="text-muted py-8 text-center text-xs">
              <p>
                {i18n.current === "ru"
                  ? "В этот день нет запланированных событий"
                  : "No scheduled events on this date"}
              </p>
            </div>
          {:else}
            {@const grouped = groupDayItems(selectedItems)}
            <div class="space-y-4">
              {#if grouped.releases.length > 0}
                <div class="space-y-2">
                  <div
                    class="flex items-center gap-1.5 px-0.5 text-xs font-bold tracking-wider text-amber-400 uppercase"
                  >
                    <Sparkles size={13} aria-hidden="true" />
                    <span>{i18n.t.views.calendarFilterOnlyRelease}</span>
                    <span class="text-muted ml-auto text-[11px] font-semibold tabular-nums">
                      {grouped.releases.length}
                    </span>
                  </div>
                  <div class="space-y-2">
                    {#each grouped.releases as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
                      {@render renderItemCard(item, true, false)}
                    {/each}
                  </div>
                </div>
              {/if}

              {#if grouped.airDates.length > 0}
                <div class="space-y-2">
                  <div
                    class="flex items-center gap-1.5 px-0.5 text-xs font-bold tracking-wider text-emerald-400 uppercase"
                  >
                    <Play size={13} aria-hidden="true" />
                    <span>{i18n.t.views.calendarFilterOnlyAirDate}</span>
                    <span class="text-muted ml-auto text-[11px] font-semibold tabular-nums">
                      {grouped.airDates.length}
                    </span>
                  </div>
                  <div class="space-y-2">
                    {#each grouped.airDates as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
                      {@render renderItemCard(item, true, false)}
                    {/each}
                  </div>
                </div>
              {/if}

              {#each grouped.autoRefreshGroups as group (group.label)}
                <div class="space-y-2">
                  <div
                    class="flex items-center gap-1.5 px-0.5 text-xs font-bold tracking-wider text-indigo-400 uppercase"
                  >
                    <RefreshCw size={13} aria-hidden="true" />
                    <span>{group.label}</span>
                    <span class="text-muted ml-auto text-[11px] font-semibold tabular-nums">
                      {group.items.length}
                    </span>
                  </div>
                  <div class="space-y-2">
                    {#each group.items as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
                      {@render renderItemCard(item, true, true)}
                    {/each}
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        {:else}
          <div class="text-muted py-8 text-center text-xs">
            <p>
              {i18n.current === "ru" ? "Выберите день в календаре" : "Select a day in the calendar"}
            </p>
          </div>
        {/if}
      </aside>
    </div>
  {:else}
    <div class="space-y-6">
      {#each visibleDays as [date, items] (date)}
        <section class="space-y-3">
          <header class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <h3 class="text-ink text-sm font-bold capitalize">{dayHeading(date)}</h3>
              {#if date === todayStr}
                <span
                  class="bg-accent ring-accent/20 rounded-full px-2 py-0.5 text-[10px] font-bold tracking-wide text-white uppercase ring-2"
                >
                  {i18n.t.views.calendarToday}
                </span>
              {:else if date === tomorrowStr}
                <span
                  class="border-accent/30 bg-accent/10 text-accent-soft rounded-full border px-2 py-0.5 text-[10px] font-bold tracking-wide uppercase"
                >
                  {i18n.t.views.calendarTomorrow}
                </span>
              {/if}
              <span class="text-muted text-xs">· {formatEventsCount(items.length)}</span>
            </div>
            {#if selectedDay}
              <button
                type="button"
                class="tap bg-card text-muted inline-flex items-center gap-1 rounded-full border border-white/10 px-2.5 py-1 text-xs font-semibold transition hover:border-white/20 hover:text-white"
                onclick={() => (selectedDay = null)}
              >
                <span aria-hidden="true">✕</span>
                <span>{i18n.t.views.calendarAllDays}</span>
              </button>
            {/if}
          </header>
          <div
            class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7"
          >
            {#each items as item (item.kind + item.mediaId + (item.episodeNumber ?? ""))}
              {@render renderFeedCard(item)}
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}
</div>
