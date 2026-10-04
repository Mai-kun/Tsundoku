<script lang="ts">
    import { Check, ChevronRight, Image as ImageIcon, Plus, Search, Star, X } from "$shared/ui/Icons.svelte";
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
    import { i18n } from "$shared/i18n/index.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import ExternalDetailModal from "$widgets/media-detail/ExternalDetailModal.svelte";
    import {
        MEDIA_STATUS,
        type CreateMediaPayload,
        type ExternalMedia,
        type MediaItem,
        type SearchMediaType,
        type SourceInfo,
    } from "$shared/types";

    const categories = [
        "all",
        "anime",
        "manga",
        "movie",
        "tvshow",
        "game",
        "book",
    ] as const;
    const minQueryLength = 2;
    const debounceDelay = 500;
    const fallbackPlatform = "PC";

    type SearchCategory = (typeof categories)[number];

    interface Props {
        isOpen: boolean;
        initialType?: SearchCategory;
        onClose: () => void;
        onMediaAdded: (media: MediaItem) => void;
        onMediaRemoved?: (id: string) => void;
        onNavigateToMedia?: (id: string) => void;
    }

    let {
        isOpen,
        initialType = "all",
        onClose,
        onMediaAdded,
        onMediaRemoved = () => {},
        onNavigateToMedia = () => {},
    }: Props = $props();

    let query = $state("");
    let activeType = $state<SearchCategory>(untrack(() => initialType));
    let results = $state<ExternalMedia[]>([]);
    let searching = $state(false);
    let searchError = $state<unknown>(null);
    let addError = $state<unknown>(null);
    let addingKey = $state("");
    // key — library mediaId (for toggle-removal); truthy means in library
    let addedKeys = $state<Record<string, string>>({});
    let searchInput = $state<HTMLInputElement | null>(null);
    let previewItem = $state<ExternalMedia | null>(null);
    let categoryOrder = $state<string[]>([
        "anime",
        "manga",
        "movie",
        "tvshow",
        "game",
        "book",
    ]);
    let resultsByCategory = $state<Record<string, ExternalMedia[]>>({});
    let loadingByCategory = $state<Record<string, boolean>>({});
    let requestSequence = 0;
    let searchController: AbortController | null = null;
    let availableSources = $state<SourceInfo[]>([]);

    $effect(() => {
        if (isOpen) {
            void getSources()
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

    interface GroupedResult {
        category: SearchMediaType;
        title: string;
        items: ExternalMedia[];
        totalInGroup: number;
        loading: boolean;
    }

    let orderedSearchTypes = $derived.by<SearchMediaType[]>(() => {
        const typesToSearch: SearchMediaType[] = [
            "anime",
            "manga",
            "movie",
            "tvshow",
            "game",
            "book",
        ];
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
    let hasAnyResults = $derived(
        Object.values(resultsByCategory).some((items) => items.length > 0),
    );

    $effect(() => {
        if (!isOpen) return;

        const pendingTerm = term;
        const pendingType = activeType;
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

        const delay = setTimeout(
            () =>
                void loadResults(
                    pendingType,
                    pendingTerm,
                    sequence,
                    controller.signal,
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
            previewItem = null;
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
                            const isAnime =
                                (item.type === "tvshow" ||
                                    item.type === "movie") &&
                                item.isAnime;
                            const effectiveType =
                                item.type === "tvshow" && isAnime
                                    ? "anime"
                                    : item.type;
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
    ) {
        if (signal.aborted) return;

        if (type !== "all") {
            try {
                const found = await searchExternal(type, pendingTerm, signal);
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
        loadingByCategory = Object.fromEntries(
            orderedTypes.map((cat) => [cat, true]),
        );
        searching = true;
        searchError = null;
        let completedCount = 0;

        await Promise.allSettled(
            orderedTypes.map(async (cat) => {
                let found: ExternalMedia[] = [];
                try {
                    found = await searchExternal(cat, pendingTerm, signal);
                } catch {
                    found = [];
                }
                if (sequence !== requestSequence) return;

                resultsByCategory = { ...resultsByCategory, [cat]: found };
                loadingByCategory = { ...loadingByCategory, [cat]: false };
                results = orderedTypes.flatMap(
                    (c) => resultsByCategory[c] ?? [],
                );
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

    async function hydrateMissingData(
        items: ExternalMedia[],
        sequence: number,
        signal: AbortSignal,
    ) {
        const candidates = items.filter(
            (r) =>
                effectiveType(r) === "manga" &&
                (r.chapters == null || r.volumes == null || !r.author),
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
                        if (enriched.chapters != null)
                            item.chapters = enriched.chapters;
                        if (enriched.volumes != null)
                            item.volumes = enriched.volumes;
                        if (enriched.totalCount != null)
                            item.totalCount = enriched.totalCount;
                        if (enriched.author) item.author = enriched.author;
                        if (enriched.ratings && enriched.ratings.length > 0)
                            item.ratings = enriched.ratings;
                        if (enriched.rating && !item.rating)
                            item.rating = enriched.rating;
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
        return category === "anime"
            ? i18n.t.navigation.anime
            : i18n.t.types[category];
    }

    function effectiveType(result: ExternalMedia): SearchMediaType {
        return (
            (result.type as SearchMediaType) ||
            (activeType !== "all" ? activeType : "tvshow")
        );
    }

    function resultKey(result: ExternalMedia, index?: number): string {
        const base = `${result.type}:${result.externalId || result.title}`;
        return index !== undefined ? `${base}:${index}` : base;
    }

    function metaLine(result: ExternalMedia): string {
        return [
            result.releaseYear,
            result.studio,
            result.author,
            result.platform,
        ]
            .filter(Boolean)
            .join(" В· ");
    }

    function countLabel(result: ExternalMedia): string | null {
        if (result.totalCount === null || result.totalCount === undefined)
            return null;

        const type = effectiveType(result);
        const unit =
            type === "anime" || type === "tvshow"
                ? i18n.t.searchModal.countUnits.tvshow
                : type === "manga"
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
            notes: result.description,
            status: MEDIA_STATUS.planned,
            externalId: result.externalId,
            externalSource: result.externalSource,
            externalRating: result.rating,
            externalRatingVotes: result.ratingVotes,
            externalRatingsJson: result.ratings
                ? JSON.stringify(result.ratings)
                : undefined,
            releaseDate:
                result.releaseDate ??
                (result.releaseYear
                    ? `${result.releaseYear}-01-01`
                    : undefined),
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
                    romajiTitle:
                        result.romajiTitle ?? result.originalTitle ?? undefined,
                    network: result.studio,
                    durationMinutes: result.runtimeMinutes,
                    episodeDurationMinutes: result.runtimeMinutes,
                    seasons: [
                        {
                            seasonNumber: 1,
                            title: "Season 1",
                            totalEpisodes:
                                result.totalCount ??
                                result.episodes?.length ??
                                0,
                            airDate:
                                result.releaseDate ??
                                (result.releaseYear
                                    ? `${result.releaseYear}-01-01`
                                    : undefined),
                            episodesData: result.episodes
                                ? JSON.stringify(result.episodes)
                                : undefined,
                        },
                    ],
                };
            case "tvshow":
                return {
                    ...common,
                    type: "tvshow",
                    isAnime: false,
                    studio: result.studio,
                    romajiTitle:
                        result.romajiTitle ?? result.originalTitle ?? undefined,
                    network: result.studio,
                    durationMinutes: result.runtimeMinutes,
                    episodeDurationMinutes: result.runtimeMinutes,
                    seasons: result.episodes
                        ? [
                              {
                                  seasonNumber: 1,
                                  title: "Season 1",
                                  totalEpisodes:
                                      result.totalCount ??
                                      result.episodes.length,
                                  airDate:
                                      result.releaseDate ??
                                      (result.releaseYear
                                          ? `${result.releaseYear}-01-01`
                                          : undefined),
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
                    romajiTitle:
                        result.romajiTitle ?? result.originalTitle ?? undefined,
                    totalChapters:
                        result.chapters ?? result.totalCount ?? undefined,
                    totalVolumes: result.volumes ?? 1,
                    currentVolume: 1,
                };
            case "book":
                return {
                    ...common,
                    type: "book",
                    author: result.author || i18n.t.searchModal.unknownAuthor,
                    totalPages: result.totalCount,
                };
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
                    romajiTitle:
                        result.romajiTitle ?? result.originalTitle ?? undefined,
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
            if (
                result.type === "game" &&
                !result.releaseDate &&
                result.externalId
            ) {
                try {
                    const details = await getExternalDetails(
                        "game",
                        result.externalId,
                        result.title,
                        result.externalSource ?? undefined,
                    );
                    if (details) {
                        result.releaseDate =
                            details.releaseDate ?? result.releaseDate;
                        result.releaseYear =
                            details.releaseYear ?? result.releaseYear;
                        result.releaseStatus =
                            details.releaseStatus ?? result.releaseStatus;
                        result.genres = details.genres ?? result.genres;
                        result.platform = details.platform ?? result.platform;
                    }
                } catch {}
            }
            const created = await createMedia(buildPayload(result));
            addedKeys = { ...addedKeys, [key]: created.id };
            onMediaAdded(created);
            // The draft row is enough for the grid and the Activity Center picks up the rest,
            // so there is nothing left to wait for here: get out of the way.
            onClose();
        } catch (error) {
            addError = error;
        } finally {
            addingKey = "";
        }
    }


    function sourceBadgeClass(source?: string | null): string {
        const s = (source ?? "").toLowerCase();
        if (s.includes("anilist"))
            return "bg-[#02a9ff]/15 text-[var(--color-brand-sky)] border-[#02a9ff]/30";
        if (s.includes("mangadex"))
            return "bg-[#ff6740]/15 text-[#ff6740] border-[#ff6740]/30";
        if (
            s.includes("mal") ||
            s.includes("myanimelist") ||
            s.includes("jikan")
        )
            return "bg-[#2e51a2]/20 text-[#60a5fa] border-[#2e51a2]/30";
        if (s.includes("mangaupdate"))
            return "bg-[#3b82f6]/20 text-[var(--color-ink-faint)] border-[#3b82f6]/30";
        if (s.includes("tmdb"))
            return "bg-[#01b4e4]/15 text-[var(--color-brand-sky)] border-[#01b4e4]/30";
        if (s.includes("kitsu"))
            return "bg-[#fd755c]/15 text-[#fb923c] border-[#fd755c]/30";
        if (s.includes("rawg"))
            return "bg-white/10 text-slate-200 border-white/[0.14]";
        if (s.includes("steam"))
            return "bg-[var(--color-track-deep)] text-[var(--color-info-line)] border-[color-mix(in_oklab,var(--color-info-line)_40%,transparent)]";
        if (s.includes("igdb"))
            return "bg-[#9146ff]/20 text-[#a855f7] border-[#9146ff]/40";
        if (s.includes("openlibrary"))
            return "bg-amber-500/15 text-amber-300 border-amber-500/30";
        return "bg-white/10 text-muted border-white/[0.08]";
    }

</script>

<Modal {isOpen} {onClose} labelledBy="search-title">
    <div class="flex max-h-[85vh] min-h-[60vh] flex-col">
        <header
            class="flex shrink-0 items-start justify-between gap-4 px-5 pb-4 pt-5 sm:px-6"
        >
            <div>
                <p
                    class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
                >
                    {i18n.t.searchModal.eyebrow}
                </p>
                <h2
                    id="search-title"
                    class="mt-1 text-xl font-bold tracking-tight text-ink"
                >
                    {i18n.t.searchModal.title}
                </h2>
            </div>
            <button
                type="button"
                class="tap grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink"
                aria-label={i18n.t.common.close}
                onclick={onClose}
            >
                <X size={18} aria-hidden="true" />
            </button>
        </header>

        <div class="border-y border-border px-5 py-3 sm:px-6">
            <div class="flex items-center gap-2">
                <label class="relative block flex-1">
                    <span class="sr-only">{i18n.t.searchModal.inputLabel}</span>
                    <Search
                        size={16}
                        class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted"
                        aria-hidden="true"
                    />
                    <input
                        bind:this={searchInput}
                        bind:value={query}
                        class="h-10 w-full rounded-md border border-white/[0.08] bg-elevated pl-9 pr-3 text-sm text-white outline-none placeholder:text-zinc-500 focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                        type="search"
                        placeholder={i18n.t.searchModal.placeholder(
                            labelForCategory(activeType),
                        )}
                        autocomplete="off"
                    />
                </label>

                <label class="sr-only" for="search-category"
                    >{i18n.t.searchModal.categoriesLabel}</label
                >
                <select
                    id="search-category"
                    class="h-10 shrink-0 rounded-lg border border-white/10 bg-field px-3 text-xs font-semibold text-ink outline-none transition focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                    value={activeType}
                    onchange={(e) =>
                        (activeType = (e.currentTarget as HTMLSelectElement)
                            .value as SearchCategory)}
                >
                    {#each categories as category}
                        <option value={category}
                            >{labelForCategory(category)}</option
                        >
                    {/each}
                </select>
            </div>
        </div>

        <div class="min-h-72 flex-1 overflow-y-auto px-5 py-4 sm:px-6">
            {#if addError}<p
                    class="mb-4 rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200"
                    role="alert"
                >
                    {errorMessage(addError)}
                </p>{/if}
            {#if !canSearch}
                <div
                    class="flex min-h-64 flex-col items-center justify-center gap-3 text-center"
                >
                    <div
                        class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted"
                    >
                        <Search size={22} aria-hidden="true" />
                    </div>
                    <p class="text-sm text-muted">
                        {i18n.t.searchModal.emptyQueryTitle}
                    </p>
                    <p class="text-xs text-muted">
                        {i18n.t.searchModal.emptyQueryHint}
                    </p>
                </div>
            {:else if searching && activeType !== "all"}
                <div class="space-y-3" aria-hidden="true">
                    {#each Array(3) as _, index (index)}
                        <div class="flex gap-4 rounded-lg bg-card p-3">
                            <div
                                class="h-28 w-20 animate-pulse rounded-md bg-canvas"
                            ></div>
                            <div class="flex-1 space-y-2 py-1">
                                <div
                                    class="h-4 w-1/2 animate-pulse rounded bg-canvas"
                                ></div>
                                <div
                                    class="h-3 w-full animate-pulse rounded bg-canvas"
                                ></div>
                                <div
                                    class="h-3 w-4/5 animate-pulse rounded bg-canvas"
                                ></div>
                            </div>
                        </div>
                    {/each}
                </div>
                <p class="sr-only" role="status">
                    {i18n.t.searchModal.searching}
                </p>
            {:else if searchError}
                <div
                    class="flex min-h-64 flex-col items-center justify-center gap-2 text-center"
                >
                    <p class="text-sm text-rose-200" role="alert">
                        {errorMessage(searchError)}
                    </p>
                    <p class="text-xs text-muted">
                        {i18n.t.searchModal.errorHint}
                    </p>
                </div>
            {:else if results.length === 0 && !searching}
                <div
                    class="flex min-h-64 flex-col items-center justify-center gap-2 text-center"
                >
                    <p class="text-sm font-semibold text-ink">
                        {i18n.t.searchModal.emptyTitle}
                    </p>
                    <p class="text-xs text-muted">
                        {i18n.t.searchModal.emptyHint}
                    </p>
                </div>
            {:else if activeType === "all" && (hasAnyResults || !allSectionsSettled)}
                <!-- Grouped by category -->
                <div class="space-y-6">
                    {#each groupedResults as group (group.category)}
                        <section class="space-y-3">
                            <div
                                class="flex items-center justify-between border-b border-white/[0.07]/50 pb-2"
                            >
                                <div class="flex items-center gap-2">
                                    <h3
                                        class="text-sm font-bold uppercase tracking-wider text-accent-soft"
                                    >
                                        {group.title}
                                    </h3>
                                    {#if group.loading}
                                        <span
                                            class="h-3 w-3 animate-spin rounded-full border-2 border-accent border-t-transparent"
                                            role="status"
                                            aria-label={i18n.t.searchModal
                                                .searching}
                                        ></span>
                                    {/if}
                                </div>
                                {#if !group.loading}
                                    <button
                                        type="button"
                                        class="inline-flex items-center gap-1 text-xs font-medium text-muted transition hover:text-ink"
                                        onclick={() =>
                                            (activeType =
                                                group.category as SearchCategory)}
                                    >
                                        <span
                                            >{i18n.t.searchModal.showMoreCount(
                                                group.totalInGroup,
                                            )}</span
                                        >
                                        <ChevronRight
                                            size={14}
                                            aria-hidden="true"
                                        />
                                    </button>
                                {/if}
                            </div>

                            {#if group.loading}
                                <ul class="space-y-2.5" aria-hidden="true">
                                    {#each Array(2) as _, index (index)}
                                        <li
                                            class="flex gap-4 rounded-lg bg-card p-3"
                                        >
                                            <div
                                                class="h-24 w-16 shrink-0 animate-pulse rounded-md bg-canvas"
                                            ></div>
                                            <div class="flex-1 space-y-2 py-1">
                                                <div
                                                    class="h-4 w-1/2 animate-pulse rounded bg-canvas"
                                                ></div>
                                                <div
                                                    class="h-3 w-3/4 animate-pulse rounded bg-canvas"
                                                ></div>
                                            </div>
                                        </li>
                                    {/each}
                                </ul>
                            {:else}
                                <ul class="space-y-2.5">
                                    {#each group.items as result, idx (resultKey(result, idx))}
                                        {@const key = resultKey(result)}
                                        <div
                                            class="flex cursor-pointer gap-4 rounded-lg bg-card p-3 transition hover:bg-elevated/70"
                                            role="button"
                                            tabindex="0"
                                            onclick={() => openPreview(result)}
                                            onkeydown={(e) => {
                                                if (
                                                    e.key === "Enter" ||
                                                    e.key === " "
                                                ) {
                                                    e.preventDefault();
                                                    openPreview(result);
                                                }
                                            }}
                                        >
                                            <div
                                                class="h-24 w-16 shrink-0 overflow-hidden rounded-md bg-canvas"
                                            >
                                                {#if result.coverUrl}
                                                    <img
                                                        src={result.coverUrl}
                                                        alt={result.title}
                                                        class="h-full w-full object-cover"
                                                        loading="lazy"
                                                        decoding="async"
                                                    />
                                                {:else}
                                                    <div
                                                        class="grid h-full place-items-center text-muted"
                                                    >
                                                        <ImageIcon
                                                            size={22}
                                                            stroke-width={1.25}
                                                            aria-hidden="true"
                                                        />
                                                    </div>
                                                {/if}
                                            </div>

                                            <div
                                                class="min-w-0 flex-1 space-y-1.5"
                                            >
                                                <div
                                                    class="flex items-start justify-between gap-3"
                                                >
                                                    <div class="min-w-0">
                                                        <h4
                                                            class="truncate text-sm font-semibold text-ink"
                                                            title={result.title}
                                                        >
                                                            {result.title}
                                                        </h4>
                                                        {#if result.originalTitle}
                                                            <p
                                                                class="truncate text-xs text-muted"
                                                                title={result.originalTitle}
                                                            >
                                                                {result.originalTitle}
                                                            </p>
                                                        {/if}
                                                    </div>

                                                    {#if addedKeys[key]}
                                                        <div
                                                            class="flex items-center gap-1.5"
                                                        >
                                                            <button
                                                                type="button"
                                                                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-emerald-500/20 bg-emerald-500/10 text-emerald-400 transition hover:border-rose-500/30 hover:bg-rose-500/10 hover:text-rose-400"
                                                                title={i18n.t
                                                                    .searchModal
                                                                    .inLibrary}
                                                                disabled={Boolean(
                                                                    addingKey,
                                                                )}
                                                                onclick={(
                                                                    e,
                                                                ) => {
                                                                    e.stopPropagation();
                                                                    void addResult(
                                                                        result,
                                                                    );
                                                                }}
                                                            >
                                                                {#if addingKey === key}
                                                                    <div
                                                                        class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-rose-400 border-t-transparent"
                                                                    ></div>
                                                                {:else}
                                                                    <Check
                                                                        size={16}
                                                                        aria-hidden="true"
                                                                    />
                                                                {/if}
                                                            </button>
                                                            <button
                                                                type="button"
                                                                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/10 bg-field text-muted transition hover:border-accent hover:bg-panel hover:text-accent cursor-pointer"
                                                                title={i18n.t
                                                                    .searchModal
                                                                    .preview}
                                                                onclick={(
                                                                    e,
                                                                ) => {
                                                                    e.stopPropagation();
                                                                    const targetId =
                                                                        addedKeys[
                                                                            key
                                                                        ];
                                                                    if (
                                                                        targetId
                                                                    ) {
                                                                        onClose();
                                                                        onNavigateToMedia(
                                                                            targetId,
                                                                        );
                                                                    }
                                                                }}
                                                            >
                                                                <ChevronRight
                                                                    size={15}
                                                                    aria-hidden="true"
                                                                />
                                                            </button>
                                                        </div>
                                                    {:else}
                                                        <button
                                                            type="button"
                                                            class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/10 bg-field text-muted transition hover:border-accent hover:bg-panel hover:text-ink disabled:cursor-wait disabled:opacity-70"
                                                            title={i18n.t.common
                                                                .add}
                                                            disabled={Boolean(
                                                                addingKey,
                                                            )}
                                                            onclick={(e) => {
                                                                e.stopPropagation();
                                                                void addResult(
                                                                    result,
                                                                );
                                                            }}
                                                        >
                                                            {#if addingKey === key}
                                                                <div
                                                                    class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-accent border-t-transparent"
                                                                ></div>
                                                            {:else}
                                                                <Plus
                                                                    size={16}
                                                                    aria-hidden="true"
                                                                />
                                                            {/if}
                                                        </button>
                                                    {/if}
                                                </div>

                                                <div
                                                    class="flex flex-wrap items-center gap-2 text-xs text-muted"
                                                >
                                                    {#if result.externalSource}
                                                        <span
                                                            class={`rounded px-1.5 py-0.5 text-[10px] font-semibold border ${sourceBadgeClass(result.externalSource)}`}
                                                        >
                                                            {result.externalSource}
                                                        </span>
                                                    {/if}
                                                    {#if result.rating && (!result.externalSource || !disabledSources.has(result.externalSource.toLowerCase()))}
                                                        <span
                                                            class="flex items-center gap-0.5 font-semibold text-star"
                                                        >
                                                            <Star
                                                                size={12}
                                                                fill="currentColor"
                                                            />
                                                            {result.rating.toFixed(
                                                                1,
                                                            )}
                                                        </span>
                                                    {/if}
                                                    {#if metaLine(result)}<span
                                                            >{metaLine(
                                                                result,
                                                            )}</span
                                                        >{/if}
                                                    {#if countLabel(result)}<span
                                                            class="rounded-full bg-canvas px-2 py-0.5 text-[11px] font-semibold text-muted"
                                                            >{countLabel(
                                                                result,
                                                            )}</span
                                                        >{/if}
                                                </div>

                                                {#if result.description}
                                                    <p
                                                        class="line-clamp-2 text-xs leading-relaxed text-muted"
                                                    >
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
                            class="flex cursor-pointer gap-4 rounded-lg bg-card p-3 transition hover:bg-elevated/70"
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
                            <div
                                class="h-28 w-20 shrink-0 overflow-hidden rounded-md bg-canvas"
                            >
                                {#if result.coverUrl}
                                    <img
                                        src={result.coverUrl}
                                        alt={result.title}
                                        class="h-full w-full object-cover"
                                        loading="lazy"
                                        decoding="async"
                                    />
                                {:else}
                                    <div
                                        class="grid h-full place-items-center text-muted"
                                    >
                                        <ImageIcon
                                            size={27}
                                            stroke-width={1.25}
                                            aria-hidden="true"
                                        />
                                    </div>
                                {/if}
                            </div>

                            <div class="min-w-0 flex-1 space-y-2">
                                <div
                                    class="flex items-start justify-between gap-3"
                                >
                                    <div class="min-w-0">
                                        <h3
                                            class="truncate text-sm font-semibold text-ink"
                                            title={result.title}
                                        >
                                            {result.title}
                                        </h3>
                                        {#if result.originalTitle}
                                            <p
                                                class="truncate text-xs text-muted"
                                                title={result.originalTitle}
                                            >
                                                {result.originalTitle}
                                            </p>
                                        {/if}
                                    </div>

                                    {#if addedKeys[key]}
                                        <div class="flex items-center gap-1.5">
                                            <button
                                                type="button"
                                                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-emerald-500/20 bg-emerald-500/10 text-emerald-400 transition hover:border-rose-500/30 hover:bg-rose-500/10 hover:text-rose-400"
                                                title={i18n.t.searchModal
                                                    .inLibrary}
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
                                                    <Check
                                                        size={16}
                                                        aria-hidden="true"
                                                    />
                                                {/if}
                                            </button>
                                            <button
                                                type="button"
                                                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/10 bg-field text-muted transition hover:border-accent hover:bg-panel hover:text-accent cursor-pointer"
                                                title={i18n.t.searchModal
                                                    .preview}
                                                onclick={(e) => {
                                                    e.stopPropagation();
                                                    const targetId =
                                                        addedKeys[key];
                                                    if (targetId) {
                                                        onClose();
                                                        onNavigateToMedia(
                                                            targetId,
                                                        );
                                                    }
                                                }}
                                            >
                                                <ChevronRight
                                                    size={15}
                                                    aria-hidden="true"
                                                />
                                            </button>
                                        </div>
                                    {:else}
                                        <button
                                            type="button"
                                            class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/10 bg-field text-muted transition hover:border-accent hover:bg-panel hover:text-ink disabled:cursor-wait disabled:opacity-70"
                                            title={i18n.t.common.add}
                                            disabled={Boolean(addingKey)}
                                            onclick={(e) => {
                                                e.stopPropagation();
                                                void addResult(result);
                                            }}
                                        >
                                            {#if addingKey === key}
                                                <div
                                                    class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-accent border-t-transparent"
                                                ></div>
                                            {:else}
                                                <Plus
                                                    size={16}
                                                    aria-hidden="true"
                                                />
                                            {/if}
                                        </button>
                                    {/if}
                                </div>

                                <div
                                    class="flex flex-wrap items-center gap-2 text-xs text-muted"
                                >
                                    {#if result.externalSource}
                                        <span
                                            class={`rounded px-1.5 py-0.5 text-[10px] font-semibold border ${sourceBadgeClass(result.externalSource)}`}
                                        >
                                            {result.externalSource}
                                        </span>
                                    {/if}
                                    {#if result.rating && (!result.externalSource || !disabledSources.has(result.externalSource.toLowerCase()))}
                                        <span
                                            class="flex items-center gap-0.5 font-semibold text-star"
                                        >
                                            <Star
                                                size={12}
                                                fill="currentColor"
                                            />
                                            {result.rating.toFixed(1)}
                                        </span>
                                    {/if}
                                    {#if metaLine(result)}<span
                                            >{metaLine(result)}</span
                                        >{/if}
                                    {#if countLabel(result)}<span
                                            class="rounded-full bg-canvas px-2 py-0.5 text-[11px] font-semibold text-muted"
                                            >{countLabel(result)}</span
                                        >{/if}
                                </div>

                                {#if result.description}
                                    <p
                                        class="line-clamp-2 text-xs leading-5 text-muted"
                                    >
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
                    class="inline-flex items-center gap-1.5 rounded-lg border border-white/10 bg-field px-3 py-2 text-xs font-semibold text-ink transition hover:border-accent hover:bg-panel hover:text-accent cursor-pointer"
                    title={i18n.t.searchModal.preview}
                    onclick={() => {
                        const targetId = addedKeys[prevKey];
                        if (targetId) {
                            onClose();
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
                    class="inline-flex items-center gap-2 rounded-lg border border-white/10 bg-field px-4 py-2 text-xs font-semibold text-ink transition hover:border-accent hover:bg-panel disabled:cursor-wait disabled:opacity-70"
                    disabled={Boolean(addingKey)}
                    onclick={() => void addResult(previewItem!)}
                >
                    {#if addingKey === prevKey}
                        <div
                            class="h-4 w-4 animate-spin rounded-full border-2 border-accent border-t-transparent"
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
