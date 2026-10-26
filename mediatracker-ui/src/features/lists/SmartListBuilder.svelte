<script lang="ts">
  import type { SmartListQuery, MediaItem } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";

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

  const sortByOptions = [
    { value: "score", label: () => i18n.t.views.smartSortScore },
    { value: "externalRating", label: () => i18n.t.views.smartSortExternalRating },
    { value: "releaseYear", label: () => i18n.t.views.smartSortReleaseYear },
    { value: "createdAt", label: () => i18n.t.views.smartSortCreatedAt },
    { value: "title", label: () => i18n.t.views.smartSortTitle },
  ];

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

<div class="space-y-5">
  <!-- Presets -->
  <div>
    <p class="text-muted mb-2 text-xs font-semibold tracking-widest uppercase">
      {i18n.t.views.smartPresets}
    </p>
    <div class="flex flex-wrap gap-2">
      {#each presets as preset (preset.icon)}
        <button
          type="button"
          class="bg-elevated text-ink inline-flex items-center gap-1.5 rounded-lg border border-white/10 px-3 py-1.5 text-xs transition hover:border-violet-400/40 hover:bg-violet-400/10 hover:text-violet-300"
          onclick={() => applyPreset(preset)}
        >
          <span>{preset.icon}</span>{preset.label()}
        </button>
      {/each}
    </div>
  </div>

  <!-- Categories -->
  <fieldset>
    <legend class="text-ink mb-2 text-sm font-medium">{i18n.t.views.smartCategories}</legend>
    <div class="flex flex-wrap gap-2">
      {#each categoryOptions as opt (opt.value)}
        {@const active = (query.categories ?? []).includes(opt.value)}
        <button
          type="button"
          class={`rounded-full border px-3 py-1 text-xs font-medium transition ${active ? "border-violet-400/60 bg-violet-400/15 text-violet-300" : "text-muted hover:text-ink border-white/10 hover:border-white/20"}`}
          onclick={() => toggleCategory(opt.value)}
          aria-pressed={active}
        >
          {opt.label()}
        </button>
      {/each}
    </div>
  </fieldset>

  <!-- Statuses -->
  <fieldset>
    <legend class="text-ink mb-2 text-sm font-medium">{i18n.t.views.smartStatuses}</legend>
    <div class="flex flex-wrap gap-2">
      {#each statusOptions as opt (opt.value)}
        {@const active = (query.statuses ?? []).includes(opt.value)}
        <button
          type="button"
          class={`rounded-full border px-3 py-1 text-xs font-medium transition ${active ? "border-amber-400/60 bg-amber-400/15 text-amber-300" : "text-muted hover:text-ink border-white/10 hover:border-white/20"}`}
          onclick={() => toggleStatus(opt.value)}
          aria-pressed={active}
        >
          {opt.label()}
        </button>
      {/each}
    </div>
  </fieldset>

  <!-- Scores & Rating -->
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartMinScore}
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
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder="1–10"
      />
    </label>
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartMinExternalRating}
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
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder="0–10"
      />
    </label>
    <label
      class="text-ink col-span-2 flex cursor-pointer items-center gap-2 pt-5 text-xs font-medium sm:col-span-1"
    >
      <input
        type="checkbox"
        checked={query.onlyUnrated ?? false}
        onchange={(e) =>
          onQueryChange({
            ...query,
            onlyUnrated: (e.currentTarget as HTMLInputElement).checked || null,
          })}
        class="rounded accent-violet-500"
      />
      {i18n.t.views.smartOnlyUnrated}
    </label>
  </div>

  <!-- Release Years -->
  <div class="grid grid-cols-2 gap-3">
    <label class="text-ink block space-y-1 text-xs font-medium">
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
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder="2000"
      />
    </label>
    <label class="text-ink block space-y-1 text-xs font-medium">
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
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder="2024"
      />
    </label>
  </div>

  <!-- Volume limits -->
  <div class="grid grid-cols-2 gap-3">
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartMaxDuration}
      <input
        type="number"
        min="1"
        value={query.maxDurationMinutes ?? ""}
        oninput={(e) =>
          onQueryChange({
            ...query,
            maxDurationMinutes: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
          })}
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder={i18n.t.views.smartMaxDurationPlaceholder}
      />
    </label>
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartMaxEpisodes}
      <input
        type="number"
        min="1"
        value={query.maxEpisodes ?? ""}
        oninput={(e) =>
          onQueryChange({
            ...query,
            maxEpisodes: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
          })}
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder={i18n.t.views.smartMaxEpisodesPlaceholder}
      />
    </label>
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartMaxPages}
      <input
        type="number"
        min="1"
        value={query.maxPages ?? ""}
        oninput={(e) =>
          onQueryChange({
            ...query,
            maxPages: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
          })}
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder={i18n.t.views.smartMaxPagesPlaceholder}
      />
    </label>
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartMaxChapters}
      <input
        type="number"
        min="1"
        value={query.maxChapters ?? ""}
        oninput={(e) =>
          onQueryChange({
            ...query,
            maxChapters: (e.currentTarget as HTMLInputElement).valueAsNumber || null,
          })}
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder={i18n.t.views.smartMaxChaptersPlaceholder}
      />
    </label>
  </div>

  <!-- Creator -->
  <label class="text-ink block space-y-1 text-xs font-medium">
    {i18n.t.views.smartCreator}
    <input
      type="text"
      value={query.creatorContains ?? ""}
      oninput={(e) =>
        onQueryChange({
          ...query,
          creatorContains: (e.currentTarget as HTMLInputElement).value || null,
        })}
      class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
      placeholder={i18n.t.views.smartCreatorPlaceholder}
    />
  </label>

  <!-- Sort & Limit -->
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartSortBy}
      <select
        value={query.sortBy ?? "createdAt"}
        onchange={(e) =>
          onQueryChange({ ...query, sortBy: (e.currentTarget as HTMLSelectElement).value })}
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
      >
        {#each sortByOptions as opt (opt.value)}
          <option value={opt.value}>{opt.label()}</option>
        {/each}
      </select>
    </label>
    <label class="text-ink block space-y-1 text-xs font-medium">
      {i18n.t.views.smartSortOrder}
      <select
        value={query.sortOrder ?? "desc"}
        onchange={(e) =>
          onQueryChange({ ...query, sortOrder: (e.currentTarget as HTMLSelectElement).value })}
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
      >
        <option value="desc">{i18n.t.views.smartSortDesc}</option>
        <option value="asc">{i18n.t.views.smartSortAsc}</option>
      </select>
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
        class="bg-canvas focus:border-accent mt-1 w-full rounded-lg border border-white/10 px-2.5 py-1.5 text-sm outline-none"
        placeholder={i18n.t.views.smartLimitPlaceholder}
      />
    </label>
  </div>
</div>
