<script lang="ts">
  import {
    ArrowRight,
    Check,
    ChevronRight,
    Image as ImageIcon,
    Plus,
    Search,
    Star,
    X,
  } from "$shared/ui/Icons";
  import { untrack } from "svelte";
  import {
    createMedia,
    deleteMedia,
    errorMessage,
    getCategoryOrder,
    getExternalDetails,
    getMedia,
    getSources,
    searchExternal,
  } from "$shared/api/api";
  import { parseMediaUrl } from "$shared/utils/urlMediaParser";
  import { showToast } from "$shared/ui/toast.svelte";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import { proxiedExternalCoverUrl } from "$entities/media/model/coverUrl";
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import ExternalDetailModal from "$widgets/media-detail/ExternalDetailModal.svelte";
  import { ChevronDown } from "$shared/ui/Icons";
  import {
    MEDIA_STATUS,
    type CreateMediaPayload,
    type ExternalMedia,
    type MediaItem,
    type SearchMediaType,
    type SourceInfo,
  } from "$shared/types";

  const categories = ["all", "anime", "manga", "movie", "tvshow", "game", "book"] as const;
  // 500ms beats natural typing pauses: every intermediate prefix used to fire a full aggregate
  // search (2-3 AniList requests for "all"), which drained the per-minute quota on one query.
  const debounceDelay = 500;
  // 3 characters instead of 2: two-char prefixes ("Тщ" from a mistyped layout) matched nothing
  // useful anywhere and still paid for the whole fan-out.
  const minQueryLength = 3;
  const fallbackPlatform = "PC";

  type SearchCategory = (typeof categories)[number];

  interface Props {
    isOpen: boolean;
    initialType?: SearchCategory;
    initialQuery?: string;
    initialSource?: string;
    /** The initialQuery names a creator (studio/author), not a title. */
    byCreator?: boolean;
    onClose: () => void;
    onMediaAdded: (media: MediaItem) => void;
    onMediaRemoved?: (id: string) => void;
    onNavigateToMedia?: (id: string) => void;
  }

  let {
    isOpen,
    initialType = "all",
    initialQuery = "",
    initialSource = "",
    byCreator = false,
    onClose,
    onMediaAdded,
    onMediaRemoved = () => {},
    onNavigateToMedia = () => {},
  }: Props = $props();

  let query = $state("");
  let activeType = $state<SearchCategory>(untrack(() => initialType));
  let results = $state.raw<ExternalMedia[]>([]);
  let searching = $state(false);
  let searchError = $state<unknown>(null);
  let addError = $state<unknown>(null);
  let addingKey = $state("");
  // key — library mediaId (for toggle-removal); truthy means in library
  let addedKeys = $state<Record<string, string>>({});
  let searchInput = $state<HTMLInputElement | null>(null);
  let previewItem = $state<ExternalMedia | null>(null);
  let categoryOrder = $state<string[]>(["anime", "manga", "movie", "tvshow", "game", "book"]);
  let resultsByCategory = $state<Record<string, ExternalMedia[]>>({});
  let loadingByCategory = $state<Record<string, boolean>>({});
  let requestSequence = 0;
  let searchController: AbortController | null = null;
  let availableSources = $state.raw<SourceInfo[]>([]);
  // "" = "All / by priority"; a concrete id pins the search to one source.
  let selectedSource = $state("");
  // The creator chip: a studio/author name restricting the search to their works.
  let creatorFilter = $state<string | null>(null);

  $effect(() => {
    // Every open re-reads the settings: a priority or enablement change made in the
    // settings modal applies to the very next open, no page reload needed.
    if (isOpen) {
      void getSources(true)
        .then((res) => {
          if (res && res.length > 0) availableSources = res;
        })
        .catch(() => {});
    }
  });

  let disabledSources = $derived(
    new Set(
      availableSources
        .filter((s) => !s.isEnabled)
        .flatMap((s) => [s.name.toLowerCase(), s.id.toLowerCase()]),
    ),
  );

  let term = $derived(query.trim());
  let canSearch = $derived(term.length >= minQueryLength);

  function sourceSupports(sourceId: string, type: SearchCategory): boolean {
    return availableSources.some(
      (s) =>
        s.isEnabled &&
        (s.id.toLowerCase() === sourceId.toLowerCase() ||
          s.name.toLowerCase() === sourceId.toLowerCase()) &&
        (type === "all" || s.mediaTypes.includes(type)),
    );
  }

  function formatSourceLabel(source: SourceInfo): string {
    if (source.id.startsWith("offline:")) {
      const cleanName = source.name.replace(/^\[Офлайн\]\s*/i, "");
      return `💾 ${cleanName} (Офлайн)`;
    }
    return source.name;
  }

  let sourceOptions = $derived.by(() => {
    const enabled = availableSources.filter(
      (s) => s.isEnabled && (activeType === "all" || s.mediaTypes.includes(activeType)),
    );
    return [
      { value: "", label: i18n.t.searchModal.allSources },
      ...enabled.map((s) => ({ value: s.id as string, label: formatSourceLabel(s) })),
    ];
  });

  let selectedSourceLabel = $derived.by(() => {
    if (!selectedSource) return i18n.t.searchModal.allSources;
    const found = availableSources.find((s) => s.id.toLowerCase() === selectedSource.toLowerCase());
    if (found) return formatSourceLabel(found);
    if (selectedSource.startsWith("offline:")) {
      const dbName = selectedSource.slice("offline:".length).replace(/\.db$/i, "");
      return `💾 ${dbName} (Офлайн)`;
    }
    return selectedSource;
  });

  let categoryOptions = $derived(
    categories.map((category) => ({
      value: category as string,
      label: labelForCategory(category),
    })),
  );

  interface GroupedResult {
    category: SearchMediaType;
    title: string;
    items: ExternalMedia[];
    totalInGroup: number;
    loading: boolean;
  }

  let orderedSearchTypes = $derived.by<SearchMediaType[]>(() => {
    const typesToSearch: SearchMediaType[] = ["anime", "manga", "movie", "tvshow", "game", "book"];
    return [
      ...categoryOrder.filter((c): c is SearchMediaType =>
        typesToSearch.includes(c as SearchMediaType),
      ),
      ...typesToSearch.filter((c) => !categoryOrder.includes(c)),
    ];
  });

  let groupedResults = $derived.by<GroupedResult[]>(() => {
    if (activeType !== "all") return [];
    const groups: GroupedResult[] = [];

    for (const cat of orderedSearchTypes) {
      const items = resultsByCategory[cat] ?? [];
      const loading = loadingByCategory[cat] === true;
      if (items.length === 0 && !loading) continue;
      groups.push({
        category: cat,
        title: labelForCategory(cat),
        items: items.slice(0, 5),
        totalInGroup: items.length,
        loading,
      });
    }

    return groups;
  });

  let allSectionsSettled = $derived(groupedResults.every((g) => !g.loading));
  let hasAnyResults = $derived(Object.values(resultsByCategory).some((items) => items.length > 0));

  $effect(() => {
    if (!isOpen) return;

    const pendingTerm = term;
    const pendingType = activeType;
    // Read inside the effect so changing the source or dropping the creator chip restarts it.
    const pendingSource = selectedSource;
    const pendingCreator = creatorFilter;
    const sequence = ++requestSequence;
    addError = null;

    if (pendingTerm.length < minQueryLength) {
      results = [];
      resultsByCategory = {};
      loadingByCategory = {};
      searching = false;
      searchError = null;
      return;
    }

    searching = true;
    searchError = null;

    // Typing must not leave stale requests running: the previous keystroke's queries are aborted so
    // the server stops working on results nobody will read and a slow earlier response can never
    // overwrite a newer one.
    searchController?.abort();
    const controller = new AbortController();
    searchController = controller;

    const parsedUrl = parseMediaUrl(pendingTerm);
    if (parsedUrl) {
      void loadUrlResult(parsedUrl, sequence, controller.signal);
      return () => {
        controller.abort();
      };
    }

    if (pendingTerm.startsWith("http://") || pendingTerm.startsWith("https://")) {
      results = [];
      resultsByCategory = {};
      loadingByCategory = {};
      searching = false;
      searchError = i18n.t.searchModal.unsupportedLinkError;
      return () => {
        controller.abort();
      };
    }

    const delay = setTimeout(
      () =>
        void loadResults(
          pendingType,
          pendingTerm,
          sequence,
          controller.signal,
          pendingSource || undefined,
          Boolean(pendingCreator),
        ),
      debounceDelay,
    );

    return () => {
      clearTimeout(delay);
      controller.abort();
    };
  });

  $effect(() => {
    if (isOpen) {
      activeType = untrack(() => initialType);
      query = untrack(() => initialQuery);
      previewItem = null;
      creatorFilter = untrack(() => (byCreator ? initialQuery : null));
      selectedSource = untrack(() => initialSource);
      searchInput?.focus();
      void getCategoryOrder()
        .then((order) => {
          if (order && order.length > 0) categoryOrder = order;
        })
        .catch(() => {});
      // Pre-populate addedKeys from current library (Bug 4: avoid duplicate add)
      void getMedia()
        .then((items) => {
          const map: Record<string, string> = {};
          for (const item of items) {
            if (item.externalId) {
              // Map by externalId using same type key as resultKey()
              // For anime tvshows, type field in ExternalMedia is 'anime'
              const isAnime = (item.type === "tvshow" || item.type === "movie") && item.isAnime;
              const effectiveType = item.type === "tvshow" && isAnime ? "anime" : item.type;
              const k = `${effectiveType}:${item.externalId}`;
              map[k] = item.id;
              // Also key by title as fallback for items without externalId type match
              map[`title:${item.title.toLowerCase()}`] = item.id;
            }
          }
          addedKeys = map;
        })
        .catch(() => {});
    }
  });

  async function loadResults(
    type: SearchCategory,
    pendingTerm: string,
    sequence: number,
    signal: AbortSignal,
    source?: string,
    byCreator?: boolean,
  ) {
    if (signal.aborted) return;

    if (type !== "all") {
      try {
        const found = await searchExternal(type, pendingTerm, signal, source, byCreator);
        if (sequence === requestSequence) {
          results = found;
          resultsByCategory = { [type]: found };
          loadingByCategory = { [type]: false };
          searching = false;
          void hydrateMissingData(found, sequence, signal);
        }
      } catch (error) {
        if (signal.aborted) return;
        if (sequence === requestSequence) {
          results = [];
          resultsByCategory = {};
          loadingByCategory = { [type]: false };
          searchError = error;
        }
      } finally {
        if (sequence === requestSequence) {
          searching = false;
        }
      }
      return;
    }

    const orderedTypes = orderedSearchTypes;

    results = [];
    resultsByCategory = {};
    loadingByCategory = Object.fromEntries(orderedTypes.map((cat) => [cat, true]));
    searching = true;
    searchError = null;
    let completedCount = 0;

    await Promise.allSettled(
      orderedTypes.map(async (cat) => {
        let found: ExternalMedia[] = [];
        try {
          found = await searchExternal(cat, pendingTerm, signal, source, byCreator);
        } catch {
          found = [];
        }
        if (sequence !== requestSequence) return;

        resultsByCategory = { ...resultsByCategory, [cat]: found };
        loadingByCategory = { ...loadingByCategory, [cat]: false };
        results = orderedTypes.flatMap((c) => resultsByCategory[c] ?? []);
        completedCount++;
        if (completedCount >= orderedTypes.length) {
          searching = false;
        }
        if (found.length > 0) {
          void hydrateMissingData(found, sequence, signal);
        }
      }),
    );
  }

  async function loadUrlResult(
    parsed: NonNullable<ReturnType<typeof parseMediaUrl>>,
    sequence: number,
    signal: AbortSignal,
  ) {
    if (signal.aborted) return;
    // The link carries its own category: jump to it so the hit renders in the right tab even when
    // the modal was left on another one ("all" included, whose sections would never fill).
    activeType = parsed.type;
    searching = true;
    searchError = null;
    results = [];
    resultsByCategory = {};
    loadingByCategory = { [parsed.type]: true };

    try {
      const details = await getExternalDetails(parsed.type, parsed.id, "", parsed.source, signal);
      if (sequence !== requestSequence || signal.aborted) return;

      if (details) {
        if (!details.type) details.type = parsed.type;
        if (!details.externalSource) details.externalSource = parsed.source;
        if (!details.externalId) details.externalId = parsed.id;
        details.isDirectUrl = true;

        results = [details];
        resultsByCategory = { [parsed.type]: [details] };
        loadingByCategory = { [parsed.type]: false };
      } else {
        results = [];
        resultsByCategory = {};
        loadingByCategory = {};
        searchError = i18n.t.searchModal.directLinkError;
      }
    } catch (error) {
      if (signal.aborted) return;
      if (sequence === requestSequence) {
        results = [];
        resultsByCategory = {};
        loadingByCategory = {};
        searchError = error;
      }
    } finally {
      if (sequence === requestSequence) {
        searching = false;
      }
    }
  }

  async function hydrateMissingData(items: ExternalMedia[], sequence: number, signal: AbortSignal) {
    const candidates = items.filter(
      (r) => effectiveType(r) === "manga" && (r.chapters == null || r.volumes == null || !r.author),
    );
    await Promise.allSettled(
      candidates.slice(0, 6).map(async (item) => {
        if (sequence !== requestSequence || signal.aborted) return;
        try {
          const enriched = await getExternalDetails(
            effectiveType(item),
            item.externalId,
            item.title,
            item.externalSource ?? undefined,
            signal,
          );
          if (sequence === requestSequence && enriched) {
            if (enriched.chapters != null) item.chapters = enriched.chapters;
            if (enriched.volumes != null) item.volumes = enriched.volumes;
            if (enriched.totalCount != null) item.totalCount = enriched.totalCount;
            if (enriched.author) item.author = enriched.author;
            if (enriched.ratings && enriched.ratings.length > 0) item.ratings = enriched.ratings;
            if (enriched.rating && !item.rating) item.rating = enriched.rating;
            results = [...results];
          }
        } catch {}
      }),
    );
  }

  function openPreview(result: ExternalMedia) {
    // The preview loads the full metadata itself (through the shared cache), so
    // opening one is nothing more than showing the hit we already have.
    previewItem = result;
  }

  function labelForCategory(category: SearchCategory): string {
    if (category === "all") return i18n.t.searchModal.allCategories;
    return category === "anime" ? i18n.t.navigation.anime : i18n.t.types[category];
  }

  function selectCategory(category: SearchCategory) {
    activeType = category;
    // A source pinned for films must not silently survive a jump to anime.
    if (selectedSource && !sourceSupports(selectedSource, category)) {
      selectedSource = "";
    }
  }

  function effectiveType(result: ExternalMedia): SearchMediaType {
    return (result.type as SearchMediaType) || (activeType !== "all" ? activeType : "tvshow");
  }

  function resultKey(result: ExternalMedia, index?: number): string {
    const base = `${result.type}:${result.externalId || result.title}`;
    return index !== undefined ? `${base}:${index}` : base;
  }

  function metaLine(result: ExternalMedia): string {
    return [result.releaseYear, result.studio, result.author, result.platform]
      .filter(Boolean)
      .join(" В· ");
  }

  function countLabel(result: ExternalMedia): string | null {
    if (result.totalCount === null || result.totalCount === undefined) return null;

    const type = effectiveType(result);
    const isNovel =
      result.type === "book" &&
      (result.mangaFormat === "light_novel" ||
        result.mangaFormat === "web_novel" ||
        result.format === "NOVEL");

    const unit =
      type === "anime" || type === "tvshow"
        ? i18n.t.searchModal.countUnits.tvshow
        : type === "manga" || isNovel
          ? i18n.t.searchModal.countUnits.manga
          : type === "movie"
            ? i18n.t.searchModal.countUnits.movie
            : type === "game"
              ? i18n.t.searchModal.countUnits.game
              : i18n.t.searchModal.countUnits.book;

    return `${result.totalCount} ${unit}`;
  }

  function buildPayload(result: ExternalMedia): CreateMediaPayload {
    const common = {
      title: result.title,
      coverUrl: result.coverUrl,
      description: result.description,
      trailerVideoId: result.trailerVideoId,
      status: MEDIA_STATUS.planned,
      externalId: result.externalId,
      externalSource: result.externalSource,
      externalRating: result.rating,
      externalRatingVotes: result.ratingVotes,
      externalRatingsJson: result.ratings ? JSON.stringify(result.ratings) : undefined,
      releaseDate:
        result.releaseDate ?? (result.releaseYear ? `${result.releaseYear}-01-01` : undefined),
      endDate: result.endDate,
      releaseStatus: result.releaseStatus,
    };

    switch (effectiveType(result)) {
      case "anime":
        return {
          ...common,
          type: "tvshow",
          isAnime: true,
          studio: result.studio,
          romajiTitle: result.romajiTitle ?? result.originalTitle ?? undefined,
          network: result.studio,
          durationMinutes: result.runtimeMinutes,
          episodeDurationMinutes: result.runtimeMinutes,
          seasons: [
            {
              seasonNumber: 1,
              title: "Season 1",
              totalEpisodes: result.totalCount ?? result.episodes?.length ?? 0,
              airDate:
                result.releaseDate ??
                (result.releaseYear ? `${result.releaseYear}-01-01` : undefined),
              episodesData: result.episodes ? JSON.stringify(result.episodes) : undefined,
            },
          ],
        };
      case "tvshow":
        return {
          ...common,
          type: "tvshow",
          isAnime: false,
          studio: result.studio,
          romajiTitle: result.romajiTitle ?? result.originalTitle ?? undefined,
          network: result.studio,
          durationMinutes: result.runtimeMinutes,
          episodeDurationMinutes: result.runtimeMinutes,
          seasons: result.episodes
            ? [
                {
                  seasonNumber: 1,
                  title: "Season 1",
                  totalEpisodes: result.totalCount ?? result.episodes.length,
                  airDate:
                    result.releaseDate ??
                    (result.releaseYear ? `${result.releaseYear}-01-01` : undefined),
                  episodesData: JSON.stringify(result.episodes),
                },
              ]
            : undefined,
        };
      case "manga":
        return {
          ...common,
          type: "manga",
          author: result.author || undefined,
          romajiTitle: result.romajiTitle ?? result.originalTitle ?? undefined,
          totalChapters: result.chapters ?? result.totalCount ?? undefined,
          totalVolumes: result.volumes ?? 1,
          currentVolume: 1,
        };
      case "book": {
        const isNovel =
          result.mangaFormat === "light_novel" ||
          result.mangaFormat === "web_novel" ||
          result.format === "NOVEL";
        return {
          ...common,
          type: "book",
          author: result.author || i18n.t.searchModal.unknownAuthor,
          format: isNovel ? "light_novel" : "book",
          totalPages: isNovel ? undefined : result.totalCount,
          totalChapters: isNovel ? (result.chapters ?? result.totalCount ?? undefined) : undefined,
          totalVolumes: isNovel ? (result.volumes ?? undefined) : undefined,
        };
      }
      case "game":
        return {
          ...common,
          type: "game",
          platform: result.platform || fallbackPlatform,
        };
      case "movie":
        return {
          ...common,
          type: "movie",
          durationMinutes: result.runtimeMinutes ?? result.totalCount,
          isAnime: result.type === "anime",
          studio: result.studio,
          romajiTitle: result.romajiTitle ?? result.originalTitle ?? undefined,
        };
    }
  }

  async function addResult(result: ExternalMedia) {
    const key = resultKey(result);
    if (addingKey) return;

    // Bug 5: toggle — if already in library, remove it
    const existingId = addedKeys[key];
    if (existingId) {
      const { [key]: _, ...rest } = addedKeys;
      addedKeys = rest;
      onMediaRemoved(existingId);
      deleteMedia(existingId).catch((error) => {
        addedKeys = { ...addedKeys, [key]: existingId };
        addError = error;
      });
      return;
    }

    addingKey = key;
    addError = null;

    try {
      if (result.type === "game" && !result.releaseDate && result.externalId) {
        try {
          const details = await getExternalDetails(
            "game",
            result.externalId,
            result.title,
            result.externalSource ?? undefined,
          );
          if (details) {
            result.releaseDate = details.releaseDate ?? result.releaseDate;
            result.releaseYear = details.releaseYear ?? result.releaseYear;
            result.releaseStatus = details.releaseStatus ?? result.releaseStatus;
            result.genres = details.genres ?? result.genres;
            result.platform = details.platform ?? result.platform;
          }
        } catch {}
      }
      const payload = buildPayload(result);

      // The duplicate guard lives on the server now: CreateMedia parks a clone candidate in
      // "Уточнить" (NeedsReview) instead of asking here, so no extra dialog can interrupt
      // bulk-adding. Refresh the review list so the badge lights up right away.
      const created = await createMedia(payload);
      addedKeys = { ...addedKeys, [key]: created.id };
      onMediaAdded(created);
      void jobsClient.refreshPendingMatches();
      // The dialog deliberately stays open: bulk-adding a run of titles is the common case, and
      // closing on the first one forces a reopen per title. The row now carries its own
      // "added" mark and a jump to the new detail.
    } catch (error) {
      addError = error;
    } finally {
      addingKey = "";
    }
  }

  function sourceBadgeClass(source?: string | null): string {
    const s = (source ?? "").toLowerCase();
    if (s.includes("anilist"))
      return "bg-[var(--color-badge-anilist-surface)] text-[var(--color-brand-sky)] border-[var(--color-badge-anilist-border)]";
    if (
      s.includes("sociallib") ||
      s.includes("ranobelib") ||
      s.includes("mangalib") ||
      s.includes("animelib") ||
      s.includes("slashlib") ||
      s.includes("hentailib")
    )
      return "bg-[var(--color-badge-sociallib-surface)] text-[var(--color-badge-sociallib-text)] border-[var(--color-badge-sociallib-border)]";
    if (s.includes("shikimori"))
      return "bg-[var(--color-badge-shikimori-surface)] text-[var(--color-badge-shikimori-text)] border-[var(--color-badge-shikimori-border)]";
    if (s.includes("mangadex"))
      return "bg-[var(--color-badge-mangadex-surface)] text-[var(--color-badge-mangadex)] border-[var(--color-badge-mangadex-border)]";
    if (s.includes("mal") || s.includes("myanimelist") || s.includes("jikan"))
      return "bg-[var(--color-badge-shikimori-surface)] text-[var(--color-badge-mal-text)] border-[var(--color-badge-shikimori-border-subtle)]";
    if (s.includes("mangaupdate"))
      return "bg-[var(--color-badge-mangaupdates-surface)] text-[var(--color-ink-faint)] border-[var(--color-badge-mangaupdates-border)]";
    if (s.includes("tmdb"))
      return "bg-[var(--color-badge-tmdb-surface)] text-[var(--color-brand-sky)] border-[var(--color-badge-tmdb-border)]";
    if (s.includes("kitsu"))
      return "bg-[var(--color-badge-kitsu-surface)] text-[var(--color-badge-kitsu-text)] border-[var(--color-badge-kitsu-border)]";
    if (s.includes("rawg")) return "bg-white/10 text-slate-200 border-white/[0.14]";
    if (s.includes("steam"))
      return "bg-[var(--color-track-deep)] text-[var(--color-info-line)] border-[color-mix(in_oklab,var(--color-info-line)_40%,transparent)]";
    if (s.includes("igdb"))
      return "bg-[var(--color-badge-igdb-surface)] text-[var(--color-badge-igdb-text)] border-[var(--color-badge-igdb-border)]";
    if (s.includes("openlibrary")) return "bg-amber-500/15 text-amber-300 border-amber-500/30";
    return "bg-white/10 text-muted border-white/[0.08]";
  }
</script>

<Modal {isOpen} {onClose} labelledBy="search-title" size="search">
  <div class="flex h-full min-h-0 flex-col">
    <header class="flex shrink-0 items-start justify-between gap-4 px-5 pt-5 pb-4 sm:px-6">
      <div>
        <p class="text-accent-soft text-xs font-semibold tracking-[0.18em] uppercase">
          {i18n.t.searchModal.eyebrow}
        </p>
        <h2 id="search-title" class="text-ink mt-1 text-xl font-bold tracking-tight">
          {i18n.t.searchModal.title}
        </h2>
      </div>
      <button
        type="button"
        class="tap text-muted hover:bg-elevated hover:text-ink grid h-9 w-9 place-items-center rounded-lg transition"
        aria-label={i18n.t.common.close}
        onclick={onClose}
      >
        <X size={18} aria-hidden="true" />
      </button>
    </header>

    <div class="border-border border-y px-5 py-3 sm:px-6">
      <div class="flex items-center gap-2">
        <label class="relative block flex-1">
          <span class="sr-only">{i18n.t.searchModal.inputLabel}</span>
          <Search
            size={16}
            class="text-muted pointer-events-none absolute top-1/2 left-3 -translate-y-1/2"
            aria-hidden="true"
          />
          <input
            bind:this={searchInput}
            bind:value={query}
            class="bg-elevated h-10 w-full rounded-md border border-white/[0.08] pr-3 pl-9 text-sm text-white outline-none placeholder:text-zinc-500 focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            type="search"
            placeholder={i18n.t.searchModal.placeholder(labelForCategory(activeType))}
            autocomplete="off"
          />
        </label>

        <label class="sr-only" for="search-category">{i18n.t.searchModal.categoriesLabel}</label>
        <PopoverMenu
          id="search-category"
          options={categoryOptions}
          selected={activeType}
          onSelect={(value) => selectCategory(value as SearchCategory)}
          label={i18n.t.searchModal.categoriesLabel}
          matchTriggerWidth
        >
          {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
            <button
              type="button"
              popovertarget={popoverTargetId}
              popovertargetaction="toggle"
              style={isOpen ? `anchor-name: ${anchorName}` : undefined}
              class="tap bg-field text-ink flex h-10 shrink-0 items-center gap-1.5 rounded-lg border border-white/10 px-3 text-xs font-semibold transition outline-none hover:border-indigo-500/40 has-[:popover-open]:border-indigo-500/60 has-[:popover-open]:ring-1 has-[:popover-open]:ring-indigo-500/30"
            >
              <span class="max-w-28 truncate" title={labelForCategory(activeType)}>
                {labelForCategory(activeType)}
              </span>
              <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
            </button>
          {/snippet}
        </PopoverMenu>

        <label class="sr-only" for="search-source">{i18n.t.searchModal.sourceLabel}</label>
        <PopoverMenu
          id="search-source"
          options={sourceOptions}
          selected={selectedSource}
          onSelect={(value) => (selectedSource = value as string)}
          label={i18n.t.searchModal.sourceLabel}
          class="max-w-sm min-w-[260px]"
        >
          {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
            <button
              type="button"
              popovertarget={popoverTargetId}
              popovertargetaction="toggle"
              style={isOpen ? `anchor-name: ${anchorName}` : undefined}
              class="tap bg-field text-ink flex h-10 shrink-0 items-center gap-1.5 rounded-lg border border-white/10 px-3 text-xs font-semibold transition outline-none hover:border-indigo-500/40 has-[:popover-open]:border-indigo-500/60 has-[:popover-open]:ring-1 has-[:popover-open]:ring-indigo-500/30"
            >
              <span class="max-w-48 truncate sm:max-w-56" title={selectedSourceLabel}>
                {selectedSourceLabel}
              </span>
              <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
            </button>
          {/snippet}
        </PopoverMenu>
      </div>

      {#if creatorFilter}
        <div class="mt-2 flex items-center gap-2">
          <span
            class="inline-flex items-center gap-1.5 rounded-full border border-indigo-500/30 bg-indigo-500/10 px-2.5 py-1 text-xs font-semibold text-[var(--color-accent-soft)]"
          >
            {i18n.t.searchModal.creatorFilter(creatorFilter)}
            <button
              type="button"
              class="hover:text-ink grid h-4 w-4 place-items-center rounded-full text-[var(--color-accent-soft)] transition"
              aria-label={i18n.t.searchModal.resetCreatorFilter}
              title={i18n.t.searchModal.resetCreatorFilter}
              onclick={() => (creatorFilter = null)}
            >
              <X size={12} aria-hidden="true" />
            </button>
          </span>
        </div>
      {/if}
    </div>

    <div class="min-h-72 flex-1 overflow-y-auto px-5 py-4 sm:px-6">
      {#if addError}<p
          class="mb-4 rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200"
          role="alert"
        >
          {errorMessage(addError)}
        </p>{/if}
      {#if !canSearch}
        <div class="flex min-h-64 flex-col items-center justify-center gap-3 text-center">
          <div class="bg-card text-muted grid h-12 w-12 place-items-center rounded-lg">
            <Search size={22} aria-hidden="true" />
          </div>
          <p class="text-muted text-sm">
            {i18n.t.searchModal.emptyQueryTitle}
          </p>
          <p class="text-muted text-xs">
            {i18n.t.searchModal.emptyQueryHint}
          </p>
        </div>
      {:else if searching && activeType !== "all"}
        <div class="space-y-3" aria-hidden="true">
          {#each Array(3) as _, index (index)}
            <div class="bg-card flex gap-4 rounded-lg p-3">
              <div class="bg-canvas h-28 w-20 animate-pulse rounded-md"></div>
              <div class="flex-1 space-y-2 py-1">
                <div class="bg-canvas h-4 w-1/2 animate-pulse rounded"></div>
                <div class="bg-canvas h-3 w-full animate-pulse rounded"></div>
                <div class="bg-canvas h-3 w-4/5 animate-pulse rounded"></div>
              </div>
            </div>
          {/each}
        </div>
        <p class="sr-only" role="status">
          {i18n.t.searchModal.searching}
        </p>
      {:else if searchError}
        <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center">
          <p class="text-sm text-rose-200" role="alert">
            {errorMessage(searchError)}
          </p>
          <p class="text-muted text-xs">
            {i18n.t.searchModal.errorHint}
          </p>
        </div>
      {:else if results.length === 0 && !searching}
        <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center">
          <p class="text-ink text-sm font-semibold">
            {i18n.t.searchModal.emptyTitle}
          </p>
          <p class="text-muted text-xs">
            {i18n.t.searchModal.emptyHint}
          </p>
        </div>
      {:else if activeType === "all" && (hasAnyResults || !allSectionsSettled)}
        <!-- Grouped by category -->
        <div class="space-y-6">
          {#each groupedResults as group (group.category)}
            <section class="space-y-3">
              <div class="border-white/[0.07]/50 flex items-center justify-between border-b pb-2">
                <div class="flex items-center gap-2">
                  <h3 class="text-accent-soft text-sm font-bold tracking-wider uppercase">
                    {group.title}
                  </h3>
                  {#if group.loading}
                    <span
                      class="border-accent h-3 w-3 animate-spin rounded-full border-2 border-t-transparent"
                      role="status"
                      aria-label={i18n.t.searchModal.searching}
                    ></span>
                  {/if}
                </div>
                {#if !group.loading}
                  <button
                    type="button"
                    class="text-muted hover:text-ink inline-flex items-center gap-1 text-xs font-medium transition"
                    onclick={() => (activeType = group.category as SearchCategory)}
                  >
                    <span>{i18n.t.searchModal.showMoreCount(group.totalInGroup)}</span>
                    <ChevronRight size={14} aria-hidden="true" />
                  </button>
                {/if}
              </div>

              {#if group.loading}
                <ul class="space-y-2.5" aria-hidden="true">
                  {#each Array(2) as _, index (index)}
                    <li class="bg-card flex gap-4 rounded-lg p-3">
                      <div class="bg-canvas h-24 w-16 shrink-0 animate-pulse rounded-md"></div>
                      <div class="flex-1 space-y-2 py-1">
                        <div class="bg-canvas h-4 w-1/2 animate-pulse rounded"></div>
                        <div class="bg-canvas h-3 w-3/4 animate-pulse rounded"></div>
                      </div>
                    </li>
                  {/each}
                </ul>
              {:else}
                <ul class="space-y-2.5">
                  {#each group.items as result, idx (resultKey(result, idx))}
                    {@const key = resultKey(result)}
                    <div
                      class="bg-card hover:bg-elevated/70 flex cursor-pointer gap-4 rounded-lg p-3 transition"
                      role="button"
                      tabindex="0"
                      onclick={() => openPreview(result)}
                      onkeydown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          openPreview(result);
                        }
                      }}
                    >
                      <div class="bg-canvas h-24 w-16 shrink-0 overflow-hidden rounded-md">
                        {#if result.coverUrl}
                          <img
                            src={proxiedExternalCoverUrl(result.coverUrl)}
                            alt={result.title}
                            class="h-full w-full object-cover"
                            loading="lazy"
                            decoding="async"
                            referrerpolicy="no-referrer"
                          />
                        {:else}
                          <div class="text-muted grid h-full place-items-center">
                            <ImageIcon size={22} stroke-width={1.25} aria-hidden="true" />
                          </div>
                        {/if}
                      </div>

                      <div class="min-w-0 flex-1 space-y-1.5">
                        <div class="flex items-start justify-between gap-3">
                          <div class="min-w-0">
                            <h4
                              class="text-ink truncate text-sm font-semibold"
                              title={result.title}
                            >
                              {result.title}
                            </h4>
                            {#if result.originalTitle}
                              <p class="text-muted truncate text-xs" title={result.originalTitle}>
                                {result.originalTitle}
                              </p>
                            {/if}
                          </div>

                          {#if addedKeys[key]}
                            <div class="flex items-center gap-1.5">
                              <button
                                type="button"
                                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-emerald-500/20 bg-emerald-500/10 text-emerald-400 transition hover:border-rose-500/30 hover:bg-rose-500/10 hover:text-rose-400 disabled:cursor-wait disabled:opacity-70"
                                title={i18n.t.searchModal.added}
                                aria-label={i18n.t.searchModal.added}
                                disabled={Boolean(addingKey)}
                                onclick={(e) => {
                                  e.stopPropagation();
                                  void addResult(result);
                                }}
                              >
                                {#if addingKey === key}
                                  <div
                                    class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-rose-400 border-t-transparent"
                                  ></div>
                                {:else}
                                  <Check size={14} aria-hidden="true" />
                                {/if}
                              </button>
                              <button
                                type="button"
                                class="bg-panel text-muted hover:border-accent hover:text-accent flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-full border border-white/10 transition"
                                title={i18n.t.searchModal.goToTitle}
                                aria-label={i18n.t.searchModal.goToTitle}
                                onclick={(e) => {
                                  e.stopPropagation();
                                  const targetId = addedKeys[key];
                                  if (targetId) {
                                    // No onClose() here: the parent's onNavigateToMedia handler
                                    // closes the modal itself. Closing twice queues two
                                    // history.back() calls that eat the route entry openDetail
                                    // is about to push, so the media page never opens.
                                    onNavigateToMedia(targetId);
                                  }
                                }}
                              >
                                <ArrowRight size={16} aria-hidden="true" />
                              </button>
                            </div>
                          {:else}
                            <button
                              type="button"
                              class="bg-field text-muted hover:border-accent hover:bg-panel hover:text-ink flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/10 transition disabled:cursor-wait disabled:opacity-70"
                              title={i18n.t.common.add}
                              disabled={Boolean(addingKey)}
                              onclick={(e) => {
                                e.stopPropagation();
                                void addResult(result);
                              }}
                            >
                              {#if addingKey === key}
                                <div
                                  class="border-accent h-3.5 w-3.5 animate-spin rounded-full border-2 border-t-transparent"
                                ></div>
                              {:else}
                                <Plus size={16} aria-hidden="true" />
                              {/if}
                            </button>
                          {/if}
                        </div>

                        <div class="text-muted flex flex-wrap items-center gap-2 text-xs">
                          {#if result.isDirectUrl}
                            <span
                              class="rounded border border-emerald-500/40 bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-300"
                            >
                              {i18n.t.searchModal.foundViaDirectLink}
                            </span>
                          {/if}
                          {#if result.externalSource}
                            <span
                              class={`rounded border px-1.5 py-0.5 text-[10px] font-semibold ${sourceBadgeClass(result.externalSource)}`}
                            >
                              {result.externalSource}
                            </span>
                          {/if}
                          {#if result.type === "book" && (result.mangaFormat === "light_novel" || result.mangaFormat === "web_novel" || result.format === "NOVEL")}
                            <span
                              class="rounded border border-purple-500/30 bg-purple-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-purple-300"
                            >
                              {i18n.current === "ru" ? "Ранобэ" : "Light Novel"}
                            </span>
                          {/if}
                          {#if result.rating && (!result.externalSource || !disabledSources.has(result.externalSource.toLowerCase()))}
                            <span class="text-star flex items-center gap-0.5 font-semibold">
                              <Star size={12} fill="currentColor" />
                              {result.rating.toFixed(1)}
                            </span>
                          {/if}
                          {#if metaLine(result)}<span>{metaLine(result)}</span>{/if}
                          {#if countLabel(result)}<span
                              class="bg-canvas text-muted rounded-full px-2 py-0.5 text-[11px] font-semibold"
                              >{countLabel(result)}</span
                            >{/if}
                        </div>

                        {#if result.description}
                          <p class="text-muted line-clamp-2 text-xs leading-relaxed">
                            {result.description}
                          </p>
                        {/if}
                      </div>
                    </div>
                  {/each}
                </ul>
              {/if}
            </section>
          {/each}
        </div>
      {:else}
        <!-- Single category list -->
        <ul class="space-y-3">
          {#each results as result, idx (resultKey(result, idx))}
            {@const key = resultKey(result)}
            <div
              class="bg-card hover:bg-elevated/70 flex cursor-pointer gap-4 rounded-lg p-3 transition"
              role="button"
              tabindex="0"
              onclick={() => openPreview(result)}
              onkeydown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  openPreview(result);
                }
              }}
            >
              <div class="bg-canvas h-28 w-20 shrink-0 overflow-hidden rounded-md">
                {#if result.coverUrl}
                  <img
                    src={proxiedExternalCoverUrl(result.coverUrl)}
                    alt={result.title}
                    class="h-full w-full object-cover"
                    loading="lazy"
                    decoding="async"
                    referrerpolicy="no-referrer"
                  />
                {:else}
                  <div class="text-muted grid h-full place-items-center">
                    <ImageIcon size={27} stroke-width={1.25} aria-hidden="true" />
                  </div>
                {/if}
              </div>

              <div class="min-w-0 flex-1 space-y-2">
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <h3 class="text-ink truncate text-sm font-semibold" title={result.title}>
                      {result.title}
                    </h3>
                    {#if result.originalTitle}
                      <p class="text-muted truncate text-xs" title={result.originalTitle}>
                        {result.originalTitle}
                      </p>
                    {/if}
                  </div>

                  {#if addedKeys[key]}
                    <div class="flex items-center gap-1.5">
                      <button
                        type="button"
                        class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-emerald-500/20 bg-emerald-500/10 text-emerald-400 transition hover:border-rose-500/30 hover:bg-rose-500/10 hover:text-rose-400 disabled:cursor-wait disabled:opacity-70"
                        title={i18n.t.searchModal.added}
                        aria-label={i18n.t.searchModal.added}
                        disabled={Boolean(addingKey)}
                        onclick={(e) => {
                          e.stopPropagation();
                          void addResult(result);
                        }}
                      >
                        {#if addingKey === key}
                          <div
                            class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-rose-400 border-t-transparent"
                          ></div>
                        {:else}
                          <Check size={14} aria-hidden="true" />
                        {/if}
                      </button>
                      <button
                        type="button"
                        class="bg-panel text-muted hover:border-accent hover:text-accent flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-full border border-white/10 transition"
                        title={i18n.t.searchModal.goToTitle}
                        aria-label={i18n.t.searchModal.goToTitle}
                        onclick={(e) => {
                          e.stopPropagation();
                          const targetId = addedKeys[key];
                          if (targetId) {
                            onClose();
                            onNavigateToMedia(targetId);
                          }
                        }}
                      >
                        <ArrowRight size={16} aria-hidden="true" />
                      </button>
                    </div>
                  {:else}
                    <button
                      type="button"
                      class="bg-field text-muted hover:border-accent hover:bg-panel hover:text-ink flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/10 transition disabled:cursor-wait disabled:opacity-70"
                      title={i18n.t.common.add}
                      disabled={Boolean(addingKey)}
                      onclick={(e) => {
                        e.stopPropagation();
                        void addResult(result);
                      }}
                    >
                      {#if addingKey === key}
                        <div
                          class="border-accent h-3.5 w-3.5 animate-spin rounded-full border-2 border-t-transparent"
                        ></div>
                      {:else}
                        <Plus size={16} aria-hidden="true" />
                      {/if}
                    </button>
                  {/if}
                </div>

                <div class="text-muted flex flex-wrap items-center gap-2 text-xs">
                  {#if result.isDirectUrl}
                    <span
                      class="rounded border border-emerald-500/40 bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-300"
                    >
                      {i18n.t.searchModal.foundViaDirectLink}
                    </span>
                  {/if}
                  {#if result.externalSource}
                    <span
                      class={`rounded border px-1.5 py-0.5 text-[10px] font-semibold ${sourceBadgeClass(result.externalSource)}`}
                    >
                      {result.externalSource}
                    </span>
                  {/if}
                  {#if result.type === "book" && (result.mangaFormat === "light_novel" || result.mangaFormat === "web_novel" || result.format === "NOVEL")}
                    <span
                      class="rounded border border-purple-500/30 bg-purple-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-purple-300"
                    >
                      {i18n.current === "ru" ? "Ранобэ" : "Light Novel"}
                    </span>
                  {/if}
                  {#if result.rating && (!result.externalSource || !disabledSources.has(result.externalSource.toLowerCase()))}
                    <span class="text-star flex items-center gap-0.5 font-semibold">
                      <Star size={12} fill="currentColor" />
                      {result.rating.toFixed(1)}
                    </span>
                  {/if}
                  {#if metaLine(result)}<span>{metaLine(result)}</span>{/if}
                  {#if countLabel(result)}<span
                      class="bg-canvas text-muted rounded-full px-2 py-0.5 text-[11px] font-semibold"
                      >{countLabel(result)}</span
                    >{/if}
                </div>

                {#if result.description}
                  <p class="text-muted line-clamp-2 text-xs leading-5">
                    {result.description}
                  </p>
                {/if}
              </div>
            </div>
          {/each}
        </ul>
      {/if}
    </div>
  </div>
</Modal>

{#if previewItem}
  {@const prevKey = resultKey(previewItem)}
  <ExternalDetailModal
    item={previewItem}
    type={effectiveType(previewItem)}
    onClose={() => (previewItem = null)}
  >
    {#snippet actions()}
      {#if addedKeys[prevKey]}
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg border border-emerald-500/20 bg-emerald-500/10 px-4 py-2 text-xs font-semibold text-emerald-400 transition hover:border-rose-500/30 hover:bg-rose-500/10 hover:text-rose-400 disabled:cursor-wait"
          disabled={Boolean(addingKey)}
          onclick={() => void addResult(previewItem!)}
        >
          {#if addingKey === prevKey}
            <div
              class="h-4 w-4 animate-spin rounded-full border-2 border-rose-400 border-t-transparent"
            ></div>
            <span>{i18n.t.common.adding}</span>
          {:else}
            <Check size={16} aria-hidden="true" />
            {i18n.t.searchModal.inLibrary}
          {/if}
        </button>
        <button
          type="button"
          class="bg-field text-ink hover:border-accent hover:bg-panel hover:text-accent inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-white/10 px-3 py-2 text-xs font-semibold transition"
          title={i18n.t.searchModal.preview}
          onclick={() => {
            const targetId = addedKeys[prevKey];
            if (targetId) {
              // The parent's onNavigateToMedia handler closes the modal itself; a second
              // close would queue an extra history.back() that breaks the navigation.
              onNavigateToMedia(targetId);
            }
          }}
        >
          <span>{i18n.t.searchModal.preview}</span>
          <ChevronRight size={14} aria-hidden="true" />
        </button>
      {:else}
        <button
          type="button"
          class="bg-field text-ink hover:border-accent hover:bg-panel inline-flex items-center gap-2 rounded-lg border border-white/10 px-4 py-2 text-xs font-semibold transition disabled:cursor-wait disabled:opacity-70"
          disabled={Boolean(addingKey)}
          onclick={() => void addResult(previewItem!)}
        >
          {#if addingKey === prevKey}
            <div
              class="border-accent h-4 w-4 animate-spin rounded-full border-2 border-t-transparent"
            ></div>
            <span>{i18n.t.common.adding}</span>
          {:else}
            <Plus size={16} aria-hidden="true" />
            <span>{i18n.t.common.add}</span>
          {/if}
        </button>
      {/if}
    {/snippet}
  </ExternalDetailModal>
{/if}
