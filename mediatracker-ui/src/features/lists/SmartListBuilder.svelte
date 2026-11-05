<script lang="ts">
  import type { SmartListQuery, MediaItem } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import Select from "$shared/ui/Select.svelte";
  import { Search } from "$shared/ui/Icons";

  interface Props {
    query: SmartListQuery;
    onQueryChange: (q: SmartListQuery) => void;
    allMedia: MediaItem[];
    onMatchesChange?: (matches: MediaItem[]) => void;
  }
  let { query, onQueryChange, allMedia, onMatchesChange }: Props = $props();

  // Presets
  const presets = [
    {
      label: () => i18n.t.views.smartPresetMasterpieces,
      icon: "🏆",
      apply: () => ({ minScore: 9, sortBy: "score", sortOrder: "desc" }) as SmartListQuery,
    },
    {
      label: () => i18n.t.views.smartPresetMovieNight,
      icon: "🎬",
      apply: () =>
        ({ categories: ["movie"], statuses: [0], maxDurationMinutes: 100 }) as SmartListQuery,
    },
    {
      label: () => i18n.t.views.smartPresetShortAnime,
      icon: "⚡",
      apply: () => ({ categories: ["anime"], statuses: [0], maxEpisodes: 13 }) as SmartListQuery,
    },
    {
      label: () => i18n.t.views.smartPresetHighRated,
      icon: "💎",
      apply: () =>
        ({
          statuses: [0],
          minExternalRating: 8.0,
          sortBy: "externalRating",
          sortOrder: "desc",
        }) as SmartListQuery,
    },
    {
      label: () => i18n.t.views.smartPresetShortBooks,
      icon: "📚",
      apply: () => ({ categories: ["book"], statuses: [0], maxPages: 250 }) as SmartListQuery,
    },
  ];

  const categoryOptions = [
    { value: "game", label: () => i18n.t.views.smartCategoryGame },
    { value: "anime", label: () => i18n.t.views.smartCategoryAnime },
    { value: "manga", label: () => i18n.t.views.smartCategoryManga },
    { value: "movie", label: () => i18n.t.views.smartCategoryMovie },
    { value: "tvshow", label: () => i18n.t.views.smartCategoryTvShow },
    { value: "book", label: () => i18n.t.views.smartCategoryBook },
  ];

  const statusOptions = [
    { value: 0, label: () => i18n.t.views.smartStatusPlanned },
    { value: 1, label: () => i18n.t.views.smartStatusInProgress },
    { value: 2, label: () => i18n.t.views.smartStatusCompleted },
    { value: 3, label: () => i18n.t.views.smartStatusOnHold },
    { value: 4, label: () => i18n.t.views.smartStatusDropped },
  ];

  const releaseStatusOptions = [
    { value: "", label: () => i18n.t.views.smartReleaseStatusAny },
    { value: "FINISHED", label: () => i18n.t.views.smartReleaseStatusFinished },
    { value: "RELEASING", label: () => i18n.t.views.smartReleaseStatusReleasing },
    { value: "NOT_YET_RELEASED", label: () => i18n.t.views.smartReleaseStatusAnnounced },
  ];

  const sortByOptions = [
    { value: "score", label: () => i18n.t.views.smartSortScore },
    { value: "externalRating", label: () => i18n.t.views.smartSortExternalRating },
    { value: "releaseYear", label: () => i18n.t.views.smartSortReleaseYear },
    { value: "createdAt", label: () => i18n.t.views.smartSortCreatedAt },
    { value: "title", label: () => i18n.t.views.smartSortTitle },
  ];

  /** 2×2 объёмные лимиты: фильм/серия, серии, страницы, главы. */
  const volumeFields = $derived([
    {
      key: "duration",
      label: () => i18n.t.views.smartMaxDuration,
      placeholder: () => i18n.t.views.smartMaxDurationPlaceholder,
      unit: () => i18n.t.views.smartUnitMinutes,
      value: () => query.maxDurationMinutes ?? "",
      apply: (v: number | null) => onQueryChange({ ...query, maxDurationMinutes: v }),
    },
    {
      key: "episodes",
      label: () => i18n.t.views.smartMaxEpisodes,
      placeholder: () => i18n.t.views.smartMaxEpisodesPlaceholder,
      unit: () => i18n.t.views.smartUnitEpisodes,
      value: () => query.maxEpisodes ?? "",
      apply: (v: number | null) => onQueryChange({ ...query, maxEpisodes: v }),
    },
    {
      key: "pages",
      label: () => i18n.t.views.smartMaxPages,
      placeholder: () => i18n.t.views.smartMaxPagesPlaceholder,
      unit: () => i18n.t.views.smartUnitPages,
      value: () => query.maxPages ?? "",
      apply: (v: number | null) => onQueryChange({ ...query, maxPages: v }),
    },
    {
      key: "chapters",
      label: () => i18n.t.views.smartMaxChapters,
      placeholder: () => i18n.t.views.smartMaxChaptersPlaceholder,
      unit: () => i18n.t.views.smartUnitChapters,
      value: () => query.maxChapters ?? "",
      apply: (v: number | null) => onQueryChange({ ...query, maxChapters: v }),
    },
  ]);

  function toggleCategory(value: string) {
    const cats = query.categories ?? [];
    const next = cats.includes(value) ? cats.filter((c) => c !== value) : [...cats, value];
    onQueryChange({ ...query, categories: next.length ? next : null });
  }

  function toggleStatus(value: number) {
    const statuses = query.statuses ?? [];
    const next = statuses.includes(value)
      ? statuses.filter((s) => s !== value)
      : [...statuses, value];
    onQueryChange({ ...query, statuses: next.length ? next : null });
  }

  function applyPreset(preset: (typeof presets)[0]) {
    onQueryChange(preset.apply());
  }

  function getCreatorString(item: MediaItem): string {
    switch (item.type) {
      case "movie":
        return [item.studio, item.director].filter(Boolean).join(" ");
      case "tvshow":
      case "game":
        return item.studio ?? "";
      case "book":
      case "manga":
        return item.author ?? "";
    }
  }

  function matchesCategory(item: MediaItem, cat: string): boolean {
    switch (cat) {
      case "anime":
        return (item.type === "tvshow" || item.type === "movie") && item.isAnime === true;
      case "tvshow":
        return item.type === "tvshow" && !item.isAnime;
      case "movie":
        return item.type === "movie" && !item.isAnime;
      case "game":
        return item.type === "game";
      case "manga":
        return item.type === "manga";
      case "book":
        return item.type === "book";
      default:
        return false;
    }
  }

  // Live preview matches
  const matchedItems = $derived(evaluateLocally(allMedia, query));

  $effect(() => {
    onMatchesChange?.(matchedItems);
  });

  function evaluateLocally(items: MediaItem[], q: SmartListQuery): MediaItem[] {
    let result = items;
    if (q.categories?.length) {
      result = result.filter((item) => q.categories!.some((cat) => matchesCategory(item, cat)));
    }
    if (q.statuses?.length) {
      result = result.filter((item) => q.statuses!.includes(item.status));
    }
    if (q.onlyUnrated) {
      result = result.filter((item) => !item.score || item.score <= 0);
    } else {
      if (q.minScore != null) result = result.filter((item) => (item.score ?? 0) >= q.minScore!);
      if (q.maxScore != null) result = result.filter((item) => (item.score ?? 0) <= q.maxScore!);
    }
    if (q.minExternalRating != null)
      result = result.filter((item) => (item.externalRating ?? 0) >= q.minExternalRating!);
    if (q.releaseYearFrom != null) {
      result = result.filter((item) => {
        const year =
          item.releaseYear ?? (item.releaseDate ? new Date(item.releaseDate).getFullYear() : null);
        return year != null && year >= q.releaseYearFrom!;
      });
    }
    if (q.releaseYearTo != null) {
      result = result.filter((item) => {
        const year =
          item.releaseYear ?? (item.releaseDate ? new Date(item.releaseDate).getFullYear() : null);
        return year != null && year <= q.releaseYearTo!;
      });
    }
    if (q.maxDurationMinutes != null) {
      result = result.filter((item) => {
        if (item.type === "movie")
          return item.durationMinutes > 0 && item.durationMinutes <= q.maxDurationMinutes!;
        if (item.type === "tvshow")
          return (
            (item.episodeDurationMinutes ?? item.durationMinutes ?? 24) <= q.maxDurationMinutes!
          );
        return true;
      });
    }
    if (q.maxEpisodes != null) {
      result = result.filter((item) => {
        if (item.type === "tvshow")
          return item.totalEpisodesCount > 0 && item.totalEpisodesCount <= q.maxEpisodes!;
        return true;
      });
    }
    if (q.maxPages != null) {
      result = result.filter((item) => {
        if (item.type === "book") return item.totalPages > 0 && item.totalPages <= q.maxPages!;
        return true;
      });
    }
    if (q.maxChapters != null) {
      result = result.filter((item) => {
        if (item.type === "manga")
          return (
            item.totalChapters != null &&
            item.totalChapters > 0 &&
            item.totalChapters <= q.maxChapters!
          );
        return true;
      });
    }
    if (q.creatorContains) {
      const needle = q.creatorContains.toLowerCase();
      result = result.filter((item) => getCreatorString(item).toLowerCase().includes(needle));
    }

    const desc = q.sortOrder !== "asc";
    result = [...result].sort((a, b) => {
      switch (q.sortBy) {
        case "score": {
          const sa = a.score ?? 0;
          const sb = b.score ?? 0;
          return desc ? sb - sa : sa - sb;
        }
        case "externalRating": {
          const ra = a.externalRating ?? 0;
          const rb = b.externalRating ?? 0;
          return desc ? rb - ra : ra - rb;
        }
        case "releaseYear": {
          const ya = a.releaseYear ?? 0;
          const yb = b.releaseYear ?? 0;
          return desc ? yb - ya : ya - yb;
        }
        case "title": {
          return desc ? b.title.localeCompare(a.title) : a.title.localeCompare(b.title);
        }
        case "createdAt":
        default: {
          const ta = new Date(a.createdAt).getTime();
          const tb = new Date(b.createdAt).getTime();
          return desc ? tb - ta : ta - tb;
        }
      }
    });

    if (q.limit && q.limit > 0) result = result.slice(0, q.limit);
    return result;
  }
</script>

<div class="space-y-4">
  <!-- Пресеты: ряд карточек-чипов -->
  <section class="bg-surface/50 rounded-xl border border-white/5 p-4">
    <p class="text-muted mb-3 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartPresets}
    </p>
    <!-- Full text on purpose: a truncated preset label hides the actual filter it applies. -->
    <div class="flex flex-wrap gap-2">
      {#each presets as preset (preset.icon)}
        <button
          type="button"
          class="bg-card text-ink hover:border-violet-500/40 hover:bg-violet-500/10 inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-white/5 px-3 py-2 text-xs font-medium whitespace-nowrap transition"
          onclick={() => applyPreset(preset)}
        >
          <span aria-hidden="true">{preset.icon}</span>
          <span>{preset.label()}</span>
        </button>
      {/each}
    </div>
  </section>

  <!-- Охват библиотеки: категории + статусы -->
  <section class="bg-surface/50 rounded-xl border border-white/5 p-4">
    <p class="text-muted mb-3 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartSectionScope}
    </p>
    <div class="space-y-3">
      <div class="flex flex-wrap gap-2">
        {#each categoryOptions as opt (opt.value)}
          {@const active = (query.categories ?? []).includes(opt.value)}
          <button
            type="button"
            class={`rounded-full border px-3 py-1 text-xs font-medium transition ${active ? "border-violet-500/40 bg-violet-500/15 text-violet-300" : "text-muted hover:text-ink border-white/10 hover:border-white/20"}`}
            onclick={() => toggleCategory(opt.value)}
            aria-pressed={active}
          >
            {opt.label()}
          </button>
        {/each}
      </div>
      <div class="flex flex-wrap gap-2">
        {#each statusOptions as opt (opt.value)}
          {@const active = (query.statuses ?? []).includes(opt.value)}
          <button
            type="button"
            class={`rounded-full border px-3 py-1 text-xs font-medium transition ${active ? "border-amber-500/40 bg-amber-500/15 text-amber-300" : "text-muted hover:text-ink border-white/10 hover:border-white/20"}`}
            onclick={() => toggleStatus(opt.value)}
            aria-pressed={active}
          >
            {opt.label()}
          </button>
        {/each}
      </div>
      <!-- Release status of the work itself (manga/anime finished by the author, ongoing, announced). -->
      <label class="text-ink block w-full space-y-1 text-xs font-medium sm:max-w-64">
        {i18n.t.views.smartReleaseStatusLabel}
        <Select
          id="smart-release-status"
          options={releaseStatusOptions.map((opt) => ({ value: opt.value, label: opt.label() }))}
          value={query.releaseStatus ?? ""}
          onChange={(next) => onQueryChange({ ...query, releaseStatus: next || null })}
          class="w-full rounded-lg px-2.5 py-1.5 text-sm"
        />
      </label>
    </div>
  </section>

  <!-- Оценки и качество: одна строка -->
  <section class="bg-surface/50 rounded-xl border border-white/5 p-4">
    <p class="text-muted mb-3 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartSectionQuality}
    </p>
    <div class="flex flex-wrap items-end gap-3">
      <label class="text-ink block w-32 space-y-1 text-xs font-medium sm:w-40">
        {i18n.t.views.smartMinScore}
        <span class="relative mt-1 block">
          <span
            class="text-muted pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2"
            aria-hidden="true">★</span
          >
          <input
            type="number"
            min="1"
            max="10"
            step="1"
            value={query.minScore ?? ""}
            oninput={(e) =>
              onQueryChange({
                ...query,
                minScore: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
              })}
            class="bg-canvas focus:border-violet-500/60 w-full rounded-lg border border-white/10 py-1.5 pr-2.5 pl-7 text-sm outline-none"
            placeholder="1–10"
          />
        </span>
      </label>
      <label class="text-ink block w-32 space-y-1 text-xs font-medium sm:w-40">
        {i18n.t.views.smartMinExternalRating}
        <span class="relative mt-1 block">
          <span
            class="text-muted pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2"
            aria-hidden="true">★</span
          >
          <input
            type="number"
            min="0"
            max="10"
            step="0.1"
            value={query.minExternalRating ?? ""}
            oninput={(e) =>
              onQueryChange({
                ...query,
                minExternalRating: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
              })}
            class="bg-canvas focus:border-violet-500/60 w-full rounded-lg border border-white/10 py-1.5 pr-2.5 pl-7 text-sm outline-none"
            placeholder="0–10"
          />
        </span>
      </label>
      <label class="text-ink flex cursor-pointer items-center gap-2 pb-1.5 text-xs font-medium">
        <input
          type="checkbox"
          checked={query.onlyUnrated ?? false}
          onchange={(e) =>
            onQueryChange({
              ...query,
              onlyUnrated: (e.currentTarget as HTMLInputElement).checked || null,
            })}
          class="accent-violet-500"
        />
        {i18n.t.views.smartOnlyUnrated}
      </label>
    </div>
  </section>

  <!-- Объёмы и ограничения: сетка 2×2 -->
  <section class="bg-surface/50 rounded-xl border border-white/5 p-4">
    <p class="text-muted mb-3 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartSectionVolumes}
    </p>
    <div class="grid grid-cols-2 gap-3">
      {#each volumeFields as field (field.key)}
        <label class="text-ink block space-y-1 text-xs font-medium">
          {field.label()}
          <span class="relative mt-1 block">
            <input
              type="number"
              min="1"
              value={field.value()}
              oninput={(e) =>
                field.apply((e.currentTarget as HTMLInputElement).valueAsNumber || null)}
              class="bg-canvas focus:border-violet-500/60 w-full rounded-lg border border-white/10 py-1.5 pr-10 pl-2.5 text-sm outline-none"
              placeholder={field.placeholder()}
            />
            <span
              class="text-muted pointer-events-none absolute top-1/2 right-2.5 -translate-y-1/2 text-[11px]"
              aria-hidden="true">{field.unit()}</span
            >
          </span>
        </label>
      {/each}
    </div>
  </section>

  <!-- Период и авторство -->
  <section class="bg-surface/50 rounded-xl border border-white/5 p-4">
    <p class="text-muted mb-3 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartSectionPeriod}
    </p>
    <div class="space-y-3">
      <div class="flex items-end gap-3">
        <label class="text-ink block w-28 space-y-1 text-xs font-medium">
          {i18n.t.views.smartYearFrom}
          <input
            type="number"
            min="1900"
            max="2100"
            step="1"
            value={query.releaseYearFrom ?? ""}
            oninput={(e) =>
              onQueryChange({
                ...query,
                releaseYearFrom: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
              })}
            class="bg-canvas focus:border-violet-500/60 mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
            placeholder="2000"
          />
        </label>
        <span class="text-muted pb-2" aria-hidden="true">—</span>
        <label class="text-ink block w-28 space-y-1 text-xs font-medium">
          {i18n.t.views.smartYearTo}
          <input
            type="number"
            min="1900"
            max="2100"
            step="1"
            value={query.releaseYearTo ?? ""}
            oninput={(e) =>
              onQueryChange({
                ...query,
                releaseYearTo: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
              })}
            class="bg-canvas focus:border-violet-500/60 mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
            placeholder="2024"
          />
        </label>
      </div>
      <label class="text-ink block space-y-1 text-xs font-medium">
        {i18n.t.views.smartCreator}
        <span class="relative mt-1 block">
          <Search
            size={14}
            class="text-muted pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2"
            aria-hidden="true"
          />
          <input
            type="text"
            value={query.creatorContains ?? ""}
            oninput={(e) =>
              onQueryChange({
                ...query,
                creatorContains: (e.currentTarget as HTMLInputElement).value || null,
              })}
            class="bg-canvas focus:border-violet-500/60 w-full rounded-lg border border-white/10 py-1.5 pr-2.5 pl-8 text-sm outline-none"
            placeholder={i18n.t.views.smartCreatorPlaceholder}
          />
        </span>
      </label>
    </div>
  </section>

  <!-- Сортировка и лимит -->
  <section class="bg-surface/50 rounded-xl border border-white/5 p-4">
    <p class="text-muted mb-3 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartSectionSort}
    </p>
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
      <label class="text-ink block space-y-1 text-xs font-medium">
        {i18n.t.views.smartSortBy}
        <Select
          id="smart-sort-by"
          options={sortByOptions.map((opt) => ({ value: opt.value, label: opt.label() }))}
          value={query.sortBy ?? "createdAt"}
          onChange={(next) => onQueryChange({ ...query, sortBy: next })}
          class="w-full rounded-lg px-2.5 py-1.5 text-sm"
        />
      </label>
      <label class="text-ink block space-y-1 text-xs font-medium">
        {i18n.t.views.smartSortOrder}
        <Select
          id="smart-sort-order"
          options={[
            { value: "desc", label: i18n.t.views.smartSortDesc },
            { value: "asc", label: i18n.t.views.smartSortAsc },
          ]}
          value={query.sortOrder ?? "desc"}
          onChange={(next) => onQueryChange({ ...query, sortOrder: next })}
          class="w-full rounded-lg px-2.5 py-1.5 text-sm"
        />
      </label>
      <label class="text-ink block space-y-1 text-xs font-medium">
        {i18n.t.views.smartLimit}
        <input
          type="number"
          min="1"
          value={query.limit ?? ""}
          oninput={(e) =>
            onQueryChange({
              ...query,
              limit: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
            })}
          class="bg-canvas focus:border-violet-500/60 mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
          placeholder={i18n.t.views.smartLimitPlaceholder}
        />
      </label>
    </div>
  </section>
</div>
