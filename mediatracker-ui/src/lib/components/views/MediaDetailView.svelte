<script lang="ts">
    import ArrowLeft from "lucide-svelte/icons/arrow-left";
    import ArrowUpDown from "lucide-svelte/icons/arrow-up-down";
    import Bookmark from "lucide-svelte/icons/bookmark";
    import CalendarDays from "lucide-svelte/icons/calendar-days";
    import Check from "lucide-svelte/icons/check";
    import CheckCircle2 from "lucide-svelte/icons/check-circle-2";
    import ChevronDown from "lucide-svelte/icons/chevron-down";
    import ExternalLink from "lucide-svelte/icons/external-link";
    import Eye from "lucide-svelte/icons/eye";
    import GitBranch from "lucide-svelte/icons/git-branch";
    import ImageIcon from "lucide-svelte/icons/image";
    import Languages from "lucide-svelte/icons/languages";
    import Layers from "lucide-svelte/icons/layers";
    import LoaderCircle from "lucide-svelte/icons/loader-circle";
    import LayoutGrid from "lucide-svelte/icons/layout-grid";
    import List from "lucide-svelte/icons/list";
    import Minus from "lucide-svelte/icons/minus";
    import Pause from "lucide-svelte/icons/pause";
    import Pencil from "lucide-svelte/icons/pencil";
    import Play from "lucide-svelte/icons/play";
    import Plus from "lucide-svelte/icons/plus";
    import RefreshCw from "lucide-svelte/icons/refresh-cw";
    import RotateCcw from "lucide-svelte/icons/rotate-ccw";
    import Sparkles from "lucide-svelte/icons/sparkles";
    import Star from "lucide-svelte/icons/star";
    import Trash2 from "lucide-svelte/icons/trash-2";
    import Trophy from "lucide-svelte/icons/trophy";
    import X from "lucide-svelte/icons/x";
    import {
        addVolume,
        createMedia,
        deleteVolume,
        enrichMedia,
        errorMessage,
        getExternalDetails,
        getGameAchievements,
        getGameRecommendations,
        getGameRelated,
        getMedia,
        getSources,
        refreshMetadata,
        setProgress,
        setSeasonProgress,
        setVolumeProgress,
        translateText,
        updateMedia,
        updateStatus,
        updateVolume,
    } from "$lib/api";
    import { i18n } from "$lib/i18n/index.svelte";
    import { showToast } from "$lib/stores/toast.svelte";
    import {
        clampProgress,
        isMangaDetail,
        isTvShowDetail,
        MEDIA_STATUS,
        type AppView,
        type GameAchievementItem,
        type MangaMedia,
        type MangaVolume,
        type MediaDetail,
        type MediaItem,
        type MediaStatus,
        type SourceInfo,
        type TvSeason,
    } from "$lib/types";
    import { createProgressDebounce } from "$lib/utils/progressDebounce";
    import {
        formatNumber,
        sourceBadgeClasses,
    } from "$lib/components/media/mediaLabels";
    import {
        buildEpisodes,
        currentFormatLabel,
        dataSource,
        formatDate,
        formatMediaDisplayType,
        formatReleaseDate,
        formatRelationType,
        isAnime,
        orderOf,
        readOriginalTitle,
        readProgress,
        releaseStatusLabel,
        specRows,
        statusLabel,
        tags,
    } from "$lib/components/media/details/detailFormatters";
    import {
        createVolumeController,
        isVolumeDone,
        volumeCurrent,
        volumePercent,
        volumeProgressLabel,
        volumeTotal,
    } from "$lib/components/media/details/createVolumeController.svelte";
    import {
        buildRatingBadges,
        CATEGORY_EXPECTED_SOURCES,
        type RawRating,
    } from "$lib/components/media/details/ratingBadges";
    import type {
        EpisodeRow,
        ProgressInfo,
        RatingBadge,
        RecommendationItem,
        RelatedEntry,
        RelationGroup,
        SubTab,
        TimelineEntry,
    } from "$lib/components/media/details/detailTypes";
    import {
        loadMediaDetail,
        mediaDetailCache,
    } from "$lib/utils/mediaDetailPrefetch";
    import { createPrefetchCache } from "$lib/utils/prefetchCache";

    /** Обновление после мутации: кэш заведомо устарел, поэтому идём в сеть и перезаписываем его. */
    async function refreshMediaDetail(id: string) {
        mediaDetailCache.invalidate(id);
        return loadMediaDetail(id);
    }
    import CircularCounter from "$lib/components/common/CircularCounter.svelte";
    import PopoverMenu from "$lib/components/common/PopoverMenu.svelte";
    import Modal from "$lib/components/common/Modal.svelte";
    import DetailHeader from "$lib/components/media/details/DetailHeader.svelte";
    import DetailSidebar from "$lib/components/media/details/DetailSidebar.svelte";
    import DetailTabs from "$lib/components/media/details/DetailTabs.svelte";
    import ProgressStepper from "$lib/components/media/details/ProgressStepper.svelte";
    import RecommendationsPanel from "$lib/components/media/details/panels/RecommendationsPanel.svelte";
    import RelatedPanel from "$lib/components/media/details/panels/RelatedPanel.svelte";
    import RelatedPreviewModal from "$lib/components/media/details/panels/RelatedPreviewModal.svelte";
    import VolumeFormModal from "$lib/components/media/details/panels/VolumeFormModal.svelte";
    import VolumesPanel from "$lib/components/media/details/panels/VolumesPanel.svelte";
    import GameDetailSection from "$lib/components/media/details/sections/GameDetailSection.svelte";
    import MangaDetailSection from "$lib/components/media/details/sections/MangaDetailSection.svelte";
    import TvShowDetailSection from "$lib/components/media/details/sections/TvShowDetailSection.svelte";

    interface Props {
        mediaId: string;
        refreshKey: number;
        onBack: () => void;
        onUpdate: () => void;
        onDelete: (id: string) => Promise<void>;
        onEdit: (item: MediaItem) => void;
        onOpenRelated: (item: MediaItem) => void;
        onNavigate?: (view: AppView) => void;
    }



    let {
        mediaId,
        refreshKey,
        onBack,
        onUpdate,
        onDelete,
        onEdit,
        onOpenRelated,
        onNavigate = () => {},
    }: Props = $props();

    const statusOptions: readonly MediaStatus[] = [
        MEDIA_STATUS.planned,
        MEDIA_STATUS.inProgress,
        MEDIA_STATUS.completed,
        MEDIA_STATUS.onHold,
        MEDIA_STATUS.dropped,
    ];

    let media = $state<MediaDetail | null>(null);
    let isLoading = $state(true);
    let loadError = $state<unknown>(null);
    let requestSequence = 0;
    let trackedMediaId: string | null = null;

    let activeSubTab = $state<SubTab>("overview");
    let episodeSortOrder = $state<"asc" | "desc">("asc");
    let synopsisExpanded = $state(false);
    let userRatingPopoverOpen = $state(false);
    let availableSources = $state<SourceInfo[]>([]);

    /* Hover-opened rating menu: the close is deferred so the cursor can cross
       the gap between the star button and the score grid. */
    let ratingCloseTimer: ReturnType<typeof setTimeout> | null = null;

    function openRatingPopover() {
        if (ratingCloseTimer !== null) {
            clearTimeout(ratingCloseTimer);
            ratingCloseTimer = null;
        }
        userRatingPopoverOpen = true;
    }

    function closeRatingPopover() {
        if (ratingCloseTimer !== null) clearTimeout(ratingCloseTimer);
        ratingCloseTimer = setTimeout(hideRatingPopover, 180);
    }

    function hideRatingPopover() {
        if (ratingCloseTimer !== null) {
            clearTimeout(ratingCloseTimer);
            ratingCloseTimer = null;
        }
        userRatingPopoverOpen = false;
    }

    $effect(() => () => {
        if (ratingCloseTimer !== null) clearTimeout(ratingCloseTimer);
    });

    $effect(() => {
        void getSources()
            .then((res) => {
                if (res && res.length > 0) availableSources = res;
            })
            .catch(() => {});
    });

    let related = $state<RelatedEntry[]>([]);
    let relatedLoading = $state(false);
    let relatedError = $state<unknown>(null);
    let relatedSequence = 0;
    let relatedViewMode = $state<"grouped" | "timeline" | "grid">("grouped");
    let previewRelatedItem = $state<RelatedEntry | null>(null);
    let previewStatus = $state<MediaStatus>(MEDIA_STATUS.planned);
    let previewAddingBusy = $state(false);
    let previewRelatedLoading = $state(false);
    let isEnriching = $state(false);

    let previewRelatedBadges = $derived.by<RatingBadge[]>(() => {
        const item = previewRelatedItem;
        if (!item) return [];

        const ratings = (item.ratings ?? []).map((r) => ({
            source: r.source,
            rating: r.rating,
        }));

        // A single top-level score still deserves a badge when the source reported no list.
        const fallback = item.score
            ? {
                  source:
                      item.externalSource ||
                      (item.type === "manga" || item.type === "anime"
                          ? "AniList"
                          : "TMDB"),
                  score: item.score,
              }
            : null;

        return buildRatingBadges({
            ratings,
            fallback,
            category: item.type,
            availableSources,
            fallbackSources: CATEGORY_EXPECTED_SOURCES[item.type] ?? [
                "AniList",
            ],
        });
    });

    let recommendations = $state<RecommendationItem[]>([]);
    let recommendationsLoading = $state(false);
    let recommendationsError = $state<unknown>(null);

    let deleteBusy = $state(false);
    let deleteError = $state<unknown>(null);

    let statusValue = $state<MediaStatus>(MEDIA_STATUS.planned);
    let statusBusy = $state(false);
    let statusError = $state<unknown>(null);

    let scoreValue = $state<number | null>(null);
    let ratingBusy = $state(false);
    let ratingError = $state<unknown>(null);

    let progressValue = $state(0);
    let committedProgress = $state(0);
    let pendingSnapshot = $state<number | null>(null);
    let progressError = $state<unknown>(null);

    let selectedSeasonId = $state<string | null>(null);
    let episodeBusy = $state("");
    let refreshBusy = $state(false);
    let refreshError = $state<unknown>(null);

    const progressDebounce = createProgressDebounce({
        send: (id, value) => setProgress(id, value),
        buildRequest: (id, value) => ({
            url: `/api/media/${id}/progress`,
            body: { currentProgress: value },
        }),
        onCommitted: (value) => {
            committedProgress = value;
            if (media && media.type === "game") {
                (media as any).hoursPlayed = value;
            }
            if (progressValue === value) onUpdate();
        },
        onError: (error) => {
            progressValue = pendingSnapshot ?? committedProgress;
            committedProgress = progressValue;
            pendingSnapshot = null;
            progressError = error;
        },
    });

    let progressInfo = $derived(media ? readProgress(media) : null);
    let seasons = $derived(
        media && isTvShowDetail(media) ? (media.seasons ?? []) : [],
    );
    let seasonViews = $derived(
        seasons.map((season) => ({ season, episodes: buildEpisodes(season) })),
    );
    let season = $derived(
        seasonViews.find((view) => view.season.id === selectedSeasonId) ??
            seasonViews[0] ??
            null,
    );
    let episodes = $derived(season?.episodes ?? []);
    let sortedEpisodes = $derived.by(() => {
        const list = [...episodes];
        return episodeSortOrder === "asc" ? list : list.reverse();
    });
    let currentSeason = $derived(season?.season ?? null);
    let originalTitle = $derived(media ? readOriginalTitle(media) : null);
    let synopsisText = $derived(media?.notes?.trim() ?? "");
    let synopsisExpandable = $derived(synopsisText.length > 280);
    let isSynopsisTranslated = $state(false);
    let translatingSynopsis = $state(false);
    let translatedSynopsis = $state<string | null>(null);

    async function toggleTranslateSynopsis() {
        if (!media || !synopsisText || translatingSynopsis) return;

        if (isSynopsisTranslated) {
            isSynopsisTranslated = false;
            return;
        }

        // Check if we already have a cached translation in DB matching current language
        const targetLang = i18n.current === "en" ? "en" : "ru";
        if (
            media.translatedSynopsis &&
            media.translationLanguage === targetLang
        ) {
            translatedSynopsis = media.translatedSynopsis;
            isSynopsisTranslated = true;
            return;
        }

        if (translatedSynopsis) {
            isSynopsisTranslated = true;
            return;
        }

        translatingSynopsis = true;
        try {
            const res = await translateText(synopsisText, targetLang);
            if (res?.translatedText) {
                translatedSynopsis = res.translatedText;
                isSynopsisTranslated = true;
                // Persist to DB (fire-and-forget, don't block UI)
                updateMedia(media.id, {
                    translatedSynopsis: res.translatedText,
                    translationLanguage: targetLang,
                }).catch(() => {});
            }
        } catch (err) {
            showToast(errorMessage(err), "error");
        } finally {
            translatingSynopsis = false;
        }
    }

    let nextEpisode = $derived.by(() => {
        if (!currentSeason) return null;
        const watched = currentSeason.currentEpisode ?? 0;
        const total = currentSeason.totalEpisodes ?? 0;
        if (watched >= total) return null;
        return episodes.find((e) => e.number === watched + 1) ?? null;
    });

    function historyProgressText(): string {
        const info = progressInfo;
        if (!info) return i18n.t.detailModal.valueEmpty;
        return info.total !== null
            ? `${formatNumber(progressValue)} / ${formatNumber(info.total)}`
            : formatNumber(progressValue);
    }

    let progressPercent = $derived.by(() => {
        const info = progressInfo;
        if (!info || info.total === null || info.total <= 0) return 0;
        return Math.min(progressValue / info.total, 1) * 100;
    });

    let seasonProgressPercent = $derived.by(() => {
        if (
            !currentSeason ||
            !currentSeason.totalEpisodes ||
            currentSeason.totalEpisodes <= 0
        )
            return 0;
        return (
            Math.min(
                (currentSeason.currentEpisode ?? 0) /
                    currentSeason.totalEpisodes,
                1,
            ) * 100
        );
    });

    let externalRatings = $derived.by<RatingBadge[]>(() => {
        if (!media) return [];

        // The stored JSON is PascalCase from some providers and camelCase from others.
        let ratings: RawRating[] = [];
        if (media.externalRatingsJson) {
            try {
                const parsed = JSON.parse(media.externalRatingsJson);
                if (Array.isArray(parsed)) {
                    ratings = parsed.map((r) => {
                        const score =
                            typeof r.score === "number"
                                ? r.score
                                : typeof r.Score === "number"
                                  ? r.Score
                                  : typeof r.rating === "number"
                                    ? r.rating
                                    : typeof r.Rating === "number"
                                      ? r.Rating
                                      : null;
                        return {
                            source: (r.source ?? r.Source ?? "").trim(),
                            rating: score,
                            votes: r.votes ?? r.Votes ?? null,
                            // Present in the stored JSON means the source answered, even with 0.
                            queried: true,
                        };
                    });
                }
            } catch {}
        }

        const cat =
            (media as { isAnime?: boolean }).isAnime
                ? "anime"
                : media.type;

        return buildRatingBadges({
            ratings,
            fallback:
                typeof media.externalRating === "number" && media.externalRating > 0
                    ? {
                          source: dataSource(media),
                          score: media.externalRating,
                          votes: media.externalRatingVotes,
                      }
                    : null,
            category: cat,
            availableSources,
            fallbackSources: CATEGORY_EXPECTED_SOURCES[cat] ?? [],
        });
    });

    let mangaVolumes = $derived(
        media && isMangaDetail(media) ? (media.volumes ?? []) : [],
    );

    const volumes = createVolumeController({
        getMedia: () => media,
        reload: async () => {
            await load(mediaId, ++requestSequence, false);
        },
        // Read through a closure so a later prop swap is not captured here.
        onUpdate: () => onUpdate(),
    });

    $effect(() => {
        void refreshKey;
        const id = mediaId;
        const isNew = trackedMediaId !== id;
        trackedMediaId = id;
        void load(id, ++requestSequence, isNew);
    });

    $effect(() => {
        return () => void progressDebounce.flush(true);
    });

    // In-memory caches to prevent progress spinner / jog wheel from re-fetching
    const achievementsCache = createPrefetchCache<{
        achievements: GameAchievementItem[];
        total: number;
    }>(5 * 60 * 1000);
    const enrichedMediaIds = new Set<string>();

    // lowercase key -> the name as the source spelled it.
    let unlockedAchievementNames = $derived.by<Map<string, string>>(() => {
        if (!media || !media.unlockedAchievements) return new Map<string, string>();
        try {
            const parsed = JSON.parse(media.unlockedAchievements);
            if (Array.isArray(parsed)) {
                const map = new Map<string, string>();
                for (const entry of parsed) {
                    const original = String(entry);
                    map.set(original.toLowerCase().trim(), original);
                }
                return map;
            }
        } catch {}
        return new Map<string, string>();
    });

    async function toggleAchievement(name: string) {
        if (!media) return;
        // Match case-insensitively but persist the source spelling: lowercasing here used to rewrite
        // the stored names, so the achievement text in the DB no longer matched the source.
        const key = name.toLowerCase().trim();
        const nextMap = new Map(unlockedAchievementNames);
        const previousJson = media.unlockedAchievements ?? null;

        if (nextMap.has(key)) {
            nextMap.delete(key);
        } else {
            nextMap.set(key, name.trim());
        }

        const jsonStr = JSON.stringify(Array.from(nextMap.values()));
        media.unlockedAchievements = jsonStr;
        try {
            await updateMedia(media.id, { unlockedAchievements: jsonStr });
        } catch (err) {
            media.unlockedAchievements = previousJson;
            console.error("Failed to update unlocked achievements", err);
        }
    }

    // ponytail: operates on the list currently loaded, not on gameAchievementsTotal. When the
    // source was truncated by a cap the two differ, and marking names we never received would
    // persist entries that match nothing.
    let achievementsBusy = $state(false);

    async function toggleAllAchievements() {
        if (!media || gameAchievements.length === 0) return;

        const nextMap = new Map(unlockedAchievementNames);
        const previousJson = media.unlockedAchievements ?? null;

        if (allAchievementsUnlocked) {
            for (const ach of gameAchievements) {
                nextMap.delete(ach.name.toLowerCase().trim());
            }
        } else {
            for (const ach of gameAchievements) {
                nextMap.set(ach.name.toLowerCase().trim(), ach.name.trim());
            }
        }

        const jsonStr = JSON.stringify(Array.from(nextMap.values()));
        achievementsBusy = true;
        media.unlockedAchievements = jsonStr;
        try {
            await updateMedia(media.id, { unlockedAchievements: jsonStr });
        } catch (err) {
            media.unlockedAchievements = previousJson;
            showToast(errorMessage(err), "error");
        } finally {
            achievementsBusy = false;
        }
    }

    let gamePlatformOptions = $derived.by(() => {
        if (!media || media.type !== "game") return [];
        const opts = new Set<string>();
        if ((media as any).platform) {
            for (const p of ((media as any).platform as string).split(",")) {
                const trimmed = p.trim();
                if (trimmed) opts.add(trimmed);
            }
        }
        if (media.userPlatform && !opts.has(media.userPlatform)) {
            opts.add(media.userPlatform);
        }
        return Array.from(opts);
    });

    let watchedOnInput = $state("");
    let watchedOnDirty = $state(false);

    const WATCHED_ON_SITES = [
        "Kinopoisk",
        "Кинопоиск",
        "Netflix",
        "YouTube",
        "Okko",
        "ivi",
        "Megogo",
        "Wink",
        "Antonline",
        "Disney+",
        "Apple TV+",
        "Amazon Prime Video",
        "Hulu",
        "Max",
        "Criterion Channel",
        "Letterboxd",
    ];

    // Offers the built-in sites plus whatever this library already uses, so a second pick of the
    // same service is available without retyping it.
    let watchedOnOptions = $derived.by<string[]>(() => {
        const fromLibrary = media?.watchedOn?.trim();
        return Array.from(
            new Set([...WATCHED_ON_SITES, ...(fromLibrary ? [fromLibrary] : [])]),
        );
    });

    $effect(() => {
        // Only follow the server value while the field is untouched, so typing is not overwritten.
        if (!watchedOnDirty) watchedOnInput = media?.watchedOn ?? "";
    });

    async function saveWatchedOn() {
        if (!media) return;
        const value = watchedOnInput.trim();
        const previous = media.watchedOn ?? null;
        media.watchedOn = value || null;
        try {
            await updateMedia(media.id, {
                watchedOn: value || null,
                clearWatchedOn: !value,
            });
            watchedOnDirty = false;
        } catch (err) {
            media.watchedOn = previous;
            watchedOnDirty = false;
            showToast(errorMessage(err), "error");
        }
    }

    async function updateUserPlatform(val: string) {
        if (!media) return;
        const previous = media.userPlatform ?? null;
        media.userPlatform = val || null;
        try {
            // A null UserPlatform means "not supplied" to the server, so clearing needs the explicit
            // flag — sending the null alone silently kept the old platform forever.
            await updateMedia(media.id, {
                userPlatform: val || null,
                clearUserPlatform: !val,
            });
        } catch (err) {
            media.userPlatform = previous;
            console.error("Failed to update user platform", err);
        }
    }

    async function load(
        id: string,
        sequence: number,
        isNew: boolean,
        forceRefresh = false,
    ) {
        if (isNew) {
            if (typeof window !== "undefined") window.scrollTo(0, 0);
            const main = document.querySelector("main");
            if (main) main.scrollTop = 0;

            media = null;
            isLoading = true;
            loadError = null;
            selectedSeasonId = null;
            userRatingPopoverOpen = false;
            synopsisExpanded = false;
            isSynopsisTranslated = false;
            translatedSynopsis = null;
            translatingSynopsis = false;
            activeSubTab = "overview";
            related = [];
            relatedError = null;
            previewRelatedItem = null;
            recommendations = [];
            recommendationsError = null;
            progressError = null;
            statusError = null;
            ratingError = null;
            deleteError = null;
            deleteBusy = false;
        }

        try {
            // Префетч по наведению отдаёт готовый объект; после мутаций кэш протух — берём сеть.
            const loaded =
                isNew && !forceRefresh
                    ? await loadMediaDetail(id)
                    : await refreshMediaDetail(id);
            if (sequence !== requestSequence) return;
            media = loaded;
            syncFrom(loaded);

            if (forceRefresh) {
                if (loaded.type === "game") {
                    void loadGameAchievements(loaded, true);
                }
                // Restore cached translation if available for current language
                const targetLang = i18n.current === "en" ? "en" : "ru";
                if (
                    loaded.translatedSynopsis &&
                    loaded.translationLanguage === targetLang
                ) {
                    translatedSynopsis = loaded.translatedSynopsis;
                    isSynopsisTranslated = true;
                }
                void loadRelated(loaded, forceRefresh);
                void triggerBackgroundEnrichment(
                    loaded,
                    sequence,
                    forceRefresh,
                );
            } else {
                if (loaded.type === "game") {
                    const cached = achievementsCache.peek(loaded.id);
                    if (cached) {
                        gameAchievements = cached.achievements;
                        gameAchievementsTotal = cached.total;
                    }
                }
            }
        } catch (error) {
            console.error("[MediaDetailView] Failed to load media", id, error);
            if (sequence === requestSequence) {
                loadError = error;
                if (isNew) media = null;
            }
        } finally {
            if (sequence === requestSequence) isLoading = false;
        }
    }

    let gameAchievements = $state<GameAchievementItem[]>([]);
    let gameAchievementsTotal = $state(0);
    let gameAchievementsLoading = $state(false);

    // Declared after gameAchievements: a $derived may only read state declared above it.
    let allAchievementsUnlocked = $derived.by(() => {
        if (gameAchievements.length === 0) return false;
        return gameAchievements.every((ach) =>
            unlockedAchievementNames.has(ach.name.toLowerCase().trim()),
        );
    });

    /** The source reported more achievements than we received (hit the page cap). */
    let achievementsTruncated = $derived(
        gameAchievementsTotal > gameAchievements.length,
    );

    async function loadGameAchievements(item: MediaItem, force = false) {
        if (item.type !== "game") return;
        if (force) achievementsCache.invalidate(item.id);
        const cached = achievementsCache.peek(item.id);
        if (cached) {
            gameAchievements = cached.achievements;
            gameAchievementsTotal = cached.total;
            return;
        }
        gameAchievementsLoading = true;
        try {
            // load() отдаёт тот же промис, если запрос по этому id уже в полёте:
            // повторное открытие той же игры не создаёт второй запрос.
            const result = await achievementsCache.load(item.id, async () => {
                const res = await getGameAchievements({
                    steamAppId:
                        item.externalSource?.toLowerCase() === "steam"
                            ? item.externalId
                            : null,
                    rawgId:
                        item.externalSource?.toLowerCase() === "rawg"
                            ? item.externalId
                            : null,
                    title: item.title,
                    externalSource: item.externalSource,
                    externalId: item.externalId,
                });
                return {
                    achievements: res.achievements ?? [],
                    total: res.totalCount ?? 0,
                };
            });
            gameAchievements = result.achievements;
            gameAchievementsTotal = result.total;
        } catch {
            gameAchievements = [];
            gameAchievementsTotal = 0;
        } finally {
            gameAchievementsLoading = false;
        }
    }

    function syncFrom(item: MediaDetail) {
        statusValue = item.status;
        scoreValue = item.score;
        const info = readProgress(item);
        progressValue = info?.current ?? 0;
        committedProgress = progressValue;
        pendingSnapshot = null;
    }

    async function triggerBackgroundEnrichment(
        current: MediaDetail,
        sequence: number,
        force = false,
    ) {
        if (!current.externalId && !current.title) return;

        if (!force) {
            // Opening a card must not call any external API: the ratings, dates, runtime and studio it
            // renders all come from the local DB. Enrichment is now only an explicit user action
            // (the refresh button), so the badge list can never appear to "still be loading".
            return;
        }

        try {
            isEnriching = true;
            const enriched = await enrichMedia(current.id);
            enrichedMediaIds.add(current.id);
            if (sequence === requestSequence && enriched) {
                media = enriched;
                syncFrom(enriched);
            }
        } catch {
            enrichedMediaIds.add(current.id);
        } finally {
            isEnriching = false;
        }
    }

    async function loadRelated(item: MediaItem, forceRefresh = false) {
        const sequence = ++relatedSequence;
        relatedLoading = true;
        relatedError = null;

        try {
            const all = await getMedia();
            if (sequence !== relatedSequence) return;

            const results: RelatedEntry[] = [];

            // 1. Check local items with same franchiseId
            if (item.franchiseId) {
                const localMatches = all
                    .filter(
                        (candidate) =>
                            candidate.franchiseId === item.franchiseId &&
                            candidate.id !== item.id,
                    )
                    .toSorted(
                        (left, right) =>
                            orderOf(left) - orderOf(right) ||
                            left.title.localeCompare(right.title),
                    );

                for (const lm of localMatches) {
                    results.push({
                        id: lm.id,
                        title: lm.title,
                        coverUrl: lm.coverUrl,
                        type: lm.type,
                        localItem: lm,
                    });
                }
            }

            // 2. Query external relations for games (RAWG Game Series)
            if (item.type === "game") {
                try {
                    const gameRelated = await getGameRelated({
                        rawgId:
                            item.externalSource?.toLowerCase() === "rawg"
                                ? item.externalId
                                : null,
                        title: item.title,
                        externalSource: item.externalSource,
                        externalId: item.externalId,
                    });
                    for (const gr of gameRelated) {
                        if (
                            gr.id === item.externalId ||
                            gr.title.toLowerCase() === item.title.toLowerCase()
                        )
                            continue;
                        if (
                            results.some(
                                (r) =>
                                    r.id === gr.id ||
                                    r.title.toLowerCase() ===
                                        gr.title.toLowerCase(),
                            )
                        )
                            continue;
                        results.push({
                            id: gr.id,
                            title: gr.title,
                            coverUrl: gr.coverUrl,
                            type: "game",
                            score: gr.score,
                            releaseDate: gr.releaseDate,
                            year:
                                gr.releaseDate && gr.releaseDate.length >= 4
                                    ? parseInt(gr.releaseDate.slice(0, 4), 10)
                                    : null,
                            ratings: gr.score
                                ? [{ source: "RAWG", rating: gr.score }]
                                : null,
                            relationType:
                                i18n.current === "ru" ? "Игра" : "Game",
                            rawRelationType: "OTHER",
                        });
                    }
                } catch {}
            }

            // 3. Query external relations (AniList GraphQL for anime/manga)
            if (isAnime(item) || item.type === "manga") {
                const cacheKey = `tsundoku_relations_${item.id}`;
                if (forceRefresh) {
                    localStorage.removeItem(cacheKey);
                }
                const cachedStr = localStorage.getItem(cacheKey);
                let externalNodes: any[] = [];

                if (cachedStr) {
                    try {
                        const cached = JSON.parse(cachedStr);
                        if (
                            Date.now() - cached.timestamp < 2592000000 &&
                            Array.isArray(cached.items) &&
                            cached.items.length > 0
                        ) {
                            externalNodes = cached.items;
                        }
                    } catch {}
                }

                if (externalNodes.length === 0) {
                    const query = `
            query ($id: Int, $idMal: Int, $search: String, $type: MediaType) {
              Media(id: $id, idMal: $idMal, search: $search, type: $type) {
                id
                title { romaji english userPreferred native }
                format
                type
                status
                description(asHtml: false)
                averageScore
                duration
                episodes
                chapters
                volumes
                coverImage { extraLarge large medium }
                bannerImage
                startDate { year month day }
                endDate { year month day }
                studios(isMain: true) { nodes { name } }
                staff(perPage: 3) {
                  edges {
                    role
                    node { name { full } }
                  }
                }
                relations {
                  edges {
                    relationType
                    node {
                      id
                      title { romaji english userPreferred native }
                      format
                      type
                      status
                      description(asHtml: false)
                      averageScore
                      duration
                      episodes
                      chapters
                      volumes
                      coverImage { extraLarge large medium }
                      bannerImage
                      startDate { year month day }
                      endDate { year month day }
                      studios(isMain: true) { nodes { name } }
                      staff(perPage: 3) {
                        edges {
                          role
                          node { name { full } }
                        }
                      }
                    }
                  }
                }
              }
            }
          `;
                    const source = (item.externalSource ?? "").toLowerCase();
                    const isAniList = source.includes("anilist");
                    const isMalOrShikimori =
                        source.includes("shikimori") ||
                        source.includes("mal") ||
                        source.includes("jikan");
                    const parsedId =
                        item.externalId && /^\d+$/.test(item.externalId)
                            ? parseInt(item.externalId, 10)
                            : null;
                    const mediaType = item.type === "manga" ? "MANGA" : "ANIME";

                    let variables: Record<string, any> = { type: mediaType };
                    if (isAniList && parsedId) {
                        variables.id = parsedId;
                    } else if (isMalOrShikimori && parsedId) {
                        variables.idMal = parsedId;
                    } else {
                        variables.search =
                            (item as any).romajiTitle?.trim() ||
                            item.title.trim();
                    }

                    let res = await fetch("https://graphql.anilist.co/", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ query, variables }),
                    });

                    // Fallback if id / idMal failed to match on AniList
                    if (!res.ok && (variables.id || variables.idMal)) {
                        const fallbackSearch =
                            (item as any).romajiTitle?.trim() ||
                            item.title.trim();
                        const fallbackRes = await fetch(
                            "https://graphql.anilist.co/",
                            {
                                method: "POST",
                                headers: { "Content-Type": "application/json" },
                                body: JSON.stringify({
                                    query,
                                    variables: {
                                        search: fallbackSearch,
                                        type: mediaType,
                                    },
                                }),
                            },
                        );
                        if (fallbackRes.ok) {
                            res = fallbackRes;
                        }
                    }

                    if (res.ok) {
                        const json = await res.json();
                        const edges = json?.data?.Media?.relations?.edges ?? [];
                        externalNodes = edges.map((e: any) => {
                            const node = e.node;
                            const desc = node?.description
                                ? String(node.description)
                                      .replace(/<[^>]*>/g, "")
                                      .trim()
                                : null;
                            const score =
                                typeof node?.averageScore === "number"
                                    ? parseFloat(
                                          (node.averageScore / 10).toFixed(1),
                                      )
                                    : null;
                            const studio =
                                node?.studios?.nodes?.[0]?.name ?? null;
                            const author =
                                node?.staff?.edges?.find((st: any) =>
                                    /story|art|original|author/i.test(
                                        st?.role ?? "",
                                    ),
                                )?.node?.name?.full ??
                                node?.staff?.edges?.[0]?.node?.name?.full ??
                                null;
                            const originalTitle = node?.title?.native ?? null;
                            const romajiTitle = node?.title?.romaji ?? null;
                            const releaseDate = node?.startDate?.year
                                ? `${String(node.startDate.year).padStart(4, "0")}-${String(node.startDate.month ?? 1).padStart(2, "0")}-${String(node.startDate.day ?? 1).padStart(2, "0")}`
                                : null;
                            const endDate = node?.endDate?.year
                                ? `${String(node.endDate.year).padStart(4, "0")}-${String(node.endDate.month ?? 1).padStart(2, "0")}-${String(node.endDate.day ?? 1).padStart(2, "0")}`
                                : null;

                            return {
                                id: String(node?.id),
                                rawRelationType: e.relationType,
                                relationType: formatRelationType(
                                    e.relationType,
                                ),
                                title:
                                    node?.title?.english ||
                                    node?.title?.romaji ||
                                    node?.title?.userPreferred ||
                                    "Title",
                                originalTitle,
                                romajiTitle,
                                coverUrl:
                                    node?.coverImage?.large ??
                                    node?.coverImage?.medium ??
                                    null,
                                bannerUrl: node?.bannerImage ?? null,
                                format: node?.format ?? null,
                                type:
                                    node?.type?.toLowerCase() === "manga"
                                        ? "manga"
                                        : "anime",
                                year: node?.startDate?.year ?? null,
                                releaseDate,
                                endDate,
                                releaseStatus: node?.status ?? null,
                                score,
                                ratings: score
                                    ? [{ source: "AniList", rating: score }]
                                    : null,
                                description: desc,
                                duration:
                                    typeof node?.duration === "number"
                                        ? node.duration
                                        : null,
                                episodes: node?.episodes ?? null,
                                chapters: node?.chapters ?? null,
                                volumes: node?.volumes ?? null,
                                studio,
                                author,
                                externalSource: "AniList",
                            };
                        });
                        localStorage.setItem(
                            cacheKey,
                            JSON.stringify({
                                timestamp: Date.now(),
                                items: externalNodes,
                            }),
                        );
                    }
                }

                // Merge external nodes avoiding duplicates with local matches
                for (const ext of externalNodes) {
                    if (ext.title.toLowerCase() === item.title.toLowerCase())
                        continue;

                    const matchedLocal = all.find(
                        (m) =>
                            (m.externalId && m.externalId === ext.id) ||
                            m.title.toLowerCase() === ext.title.toLowerCase() ||
                            ((m as any).romajiTitle &&
                                (m as any).romajiTitle.toLowerCase() ===
                                    ext.title.toLowerCase()),
                    );

                    if (
                        !results.some(
                            (r) =>
                                r.id === ext.id ||
                                r.title.toLowerCase() ===
                                    ext.title.toLowerCase(),
                        )
                    ) {
                        results.push({
                            ...ext,
                            coverUrl: matchedLocal?.coverUrl || ext.coverUrl,
                            localItem: matchedLocal,
                        });
                    }
                }
            }

            if (sequence === relatedSequence) {
                related = results;
            }
        } catch (error) {
            if (sequence === relatedSequence) {
                related = [];
                relatedError = error;
            }
        } finally {
            if (sequence === relatedSequence) relatedLoading = false;
        }
    }



    let relatedGroups = $derived.by<RelationGroup[]>(() => {
        if (related.length === 0) return [];

        const main: RelatedEntry[] = [];
        const spinoffs: RelatedEntry[] = [];
        const adaptations: RelatedEntry[] = [];
        const others: RelatedEntry[] = [];

        for (const item of related) {
            const raw = (item.rawRelationType ?? "").toUpperCase();
            if (raw === "SEQUEL" || raw === "PREQUEL") {
                main.push(item);
            } else if (
                raw === "SIDE_STORY" ||
                raw === "SPIN_OFF" ||
                raw === "CHARACTER"
            ) {
                spinoffs.push(item);
            } else if (
                raw === "ADAPTATION" ||
                item.type === "manga" ||
                ["MANGA", "NOVEL", "ONE_SHOT"].includes(
                    item.format?.toUpperCase() ?? "",
                )
            ) {
                adaptations.push(item);
            } else {
                others.push(item);
            }
        }

        const groups: RelationGroup[] = [];
        if (main.length > 0) {
            groups.push({
                id: "main",
                title: i18n.t.detail.groupMain,
                items: main,
            });
        }
        if (spinoffs.length > 0) {
            groups.push({
                id: "spinoffs",
                title: i18n.t.detail.groupSpinoffs,
                items: spinoffs,
            });
        }
        if (adaptations.length > 0) {
            groups.push({
                id: "adaptations",
                title: i18n.t.detail.groupAdaptations,
                items: adaptations,
            });
        }
        if (others.length > 0) {
            groups.push({
                id: "others",
                title: i18n.t.detail.groupOthers,
                items: others,
            });
        }

        return groups;
    });

    let timelineEntries = $derived.by<TimelineEntry[]>(() => {
        if (!media) return [];

        const current: TimelineEntry = {
            id: media.id,
            title: media.title,
            coverUrl: media.coverUrl,
            year: media.releaseDate
                ? new Date(media.releaseDate).getFullYear()
                : null,
            formatDisplay: currentFormatLabel(media),
            relationType: i18n.t.detail.currentTitleBadge,
            isCurrent: true,
            localItem: media,
        };

        const items: TimelineEntry[] = [
            current,
            ...related.map(
                (r): TimelineEntry => ({
                    id: r.id,
                    title: r.title,
                    coverUrl: r.coverUrl,
                    year: r.year ?? null,
                    formatDisplay: formatMediaDisplayType(r),
                    relationType:
                        r.relationType ?? i18n.t.detail.relations.other,
                    isCurrent: false,
                    localItem: r.localItem,
                    rawItem: r,
                }),
            ),
        ];

        // Entries with a known year sort by it; the rest keep their order at the end.
        return items.sort((a, b) => {
            if (a.year !== null && b.year !== null) return a.year - b.year;
            if (a.year !== null) return -1;
            if (b.year !== null) return 1;
            return 0;
        });
    });


    async function handleRelatedClick(rel: RelatedEntry) {
        if (rel.localItem) {
            onOpenRelated(rel.localItem);
            return;
        }

        previewRelatedItem = rel;
        previewStatus = MEDIA_STATUS.planned;
        previewRelatedLoading = true;

        try {
            const details = await getExternalDetails(
                rel.type,
                rel.id,
                rel.title,
                rel.externalSource || "AniList",
            );
            if (details && previewRelatedItem?.id === rel.id) {
                previewRelatedItem = {
                    ...previewRelatedItem,
                    originalTitle:
                        details.originalTitle ||
                        previewRelatedItem.originalTitle,
                    romajiTitle:
                        (details as any).romajiTitle ||
                        details.originalTitle ||
                        previewRelatedItem.romajiTitle,
                    coverUrl: details.coverUrl || previewRelatedItem.coverUrl,
                    description:
                        details.description || previewRelatedItem.description,
                    year: details.releaseYear ?? previewRelatedItem.year,
                    releaseDate:
                        details.releaseDate ?? previewRelatedItem.releaseDate,
                    endDate: details.endDate ?? previewRelatedItem.endDate,
                    studio: details.studio || previewRelatedItem.studio,
                    author: details.author || previewRelatedItem.author,
                    score: details.rating ?? previewRelatedItem.score,
                    ratings: details.ratings ?? previewRelatedItem.ratings,
                    episodes: details.totalCount ?? previewRelatedItem.episodes,
                    duration:
                        details.runtimeMinutes ?? previewRelatedItem.duration,
                    releaseStatus:
                        details.releaseStatus ??
                        previewRelatedItem.releaseStatus,
                };
            }
        } catch {
        } finally {
            previewRelatedLoading = false;
        }
    }

    async function addRelatedToLibrary(rel: RelatedEntry, status: MediaStatus) {
        previewAddingBusy = true;
        try {
            // Ensure we have full details (including Kitsu ratings and exact release date)
            let itemDetails = rel;
            let fetchedEpisodes: any = null;
            try {
                const fetched = await getExternalDetails(
                    rel.type,
                    rel.id,
                    rel.title,
                    rel.externalSource || "AniList",
                );
                if (fetched) {
                    fetchedEpisodes = fetched.episodes;
                    itemDetails = {
                        ...rel,
                        originalTitle:
                            fetched.originalTitle || rel.originalTitle,
                        romajiTitle:
                            (fetched as any).romajiTitle ||
                            fetched.originalTitle ||
                            rel.romajiTitle,
                        coverUrl: fetched.coverUrl || rel.coverUrl,
                        description: fetched.description || rel.description,
                        year: fetched.releaseYear ?? rel.year,
                        releaseDate: fetched.releaseDate ?? rel.releaseDate,
                        endDate: fetched.endDate ?? rel.endDate,
                        releaseStatus:
                            fetched.releaseStatus ?? rel.releaseStatus,
                        studio: fetched.studio || rel.studio,
                        author: fetched.author || rel.author,
                        score: fetched.rating ?? rel.score,
                        ratings: fetched.ratings ?? rel.ratings,
                        episodes: fetched.totalCount ?? rel.episodes,
                        duration: fetched.runtimeMinutes ?? rel.duration,
                    };
                }
            } catch {}

            // Ensure current media has franchiseName or franchiseId so they are grouped together
            let franchiseName = media?.franchiseName || undefined;
            let franchiseId = media?.franchiseId || undefined;
            if (media && !franchiseId && !franchiseName) {
                franchiseName = media.title;
                try {
                    await updateMedia(media.id, { franchiseName: media.title });
                    media.franchiseName = media.title;
                } catch {}
            }

            const format = itemDetails.format?.toUpperCase() ?? "";
            const isMovie = format === "MOVIE";
            const isManga =
                itemDetails.type === "manga" ||
                ["MANGA", "NOVEL", "ONE_SHOT"].includes(format);

            const ratingsJson =
                itemDetails.ratings && itemDetails.ratings.length > 0
                    ? JSON.stringify(itemDetails.ratings)
                    : undefined;
            const releaseDate =
                itemDetails.releaseDate ??
                (itemDetails.year ? `${itemDetails.year}-01-01` : undefined);
            const endDate = itemDetails.endDate ?? undefined;

            let created: MediaItem;
            if (isMovie) {
                created = await createMedia({
                    type: "movie",
                    title: itemDetails.title,
                    status,
                    coverUrl: itemDetails.coverUrl,
                    notes: itemDetails.description,
                    durationMinutes: itemDetails.duration ?? 0,
                    isAnime: true,
                    studio: itemDetails.studio ?? undefined,
                    romajiTitle:
                        itemDetails.romajiTitle ??
                        itemDetails.originalTitle ??
                        undefined,
                    franchiseId,
                    franchiseName,
                    externalId: itemDetails.id,
                    externalSource: itemDetails.externalSource ?? "AniList",
                    externalRating: itemDetails.score ?? undefined,
                    externalRatingsJson: ratingsJson,
                    releaseDate,
                    endDate,
                    releaseStatus: itemDetails.releaseStatus ?? undefined,
                });
            } else if (isManga) {
                created = await createMedia({
                    type: "manga",
                    title: itemDetails.title,
                    status,
                    coverUrl: itemDetails.coverUrl,
                    notes: itemDetails.description,
                    author: itemDetails.author || undefined,
                    romajiTitle:
                        itemDetails.romajiTitle ??
                        itemDetails.originalTitle ??
                        undefined,
                    totalChapters: itemDetails.chapters ?? null,
                    totalVolumes: itemDetails.volumes ?? 1,
                    currentVolume: 1,
                    franchiseId,
                    franchiseName,
                    externalId: itemDetails.id,
                    externalSource: itemDetails.externalSource ?? "AniList",
                    externalRating: itemDetails.score ?? undefined,
                    externalRatingsJson: ratingsJson,
                    releaseDate,
                    endDate,
                    releaseStatus: itemDetails.releaseStatus ?? undefined,
                });
            } else {
                created = await createMedia({
                    type: "tvshow",
                    title: itemDetails.title,
                    status,
                    coverUrl: itemDetails.coverUrl,
                    notes: itemDetails.description,
                    durationMinutes: itemDetails.duration ?? undefined,
                    episodeDurationMinutes: itemDetails.duration ?? undefined,
                    isAnime: true,
                    studio: itemDetails.studio ?? undefined,
                    romajiTitle:
                        itemDetails.romajiTitle ??
                        itemDetails.originalTitle ??
                        undefined,
                    franchiseId,
                    franchiseName,
                    externalId: itemDetails.id,
                    externalSource: itemDetails.externalSource ?? "AniList",
                    externalRating: itemDetails.score ?? undefined,
                    externalRatingsJson: ratingsJson,
                    releaseDate,
                    endDate,
                    releaseStatus: itemDetails.releaseStatus ?? undefined,
                    seasons: [
                        {
                            seasonNumber: 1,
                            title: "Season 1",
                            totalEpisodes:
                                itemDetails.episodes ??
                                (fetchedEpisodes?.length || 12),
                            airDate: releaseDate,
                            episodesData:
                                fetchedEpisodes && fetchedEpisodes.length > 0
                                    ? JSON.stringify(fetchedEpisodes)
                                    : undefined,
                            status,
                        },
                    ],
                });
            }

            showToast(i18n.t.searchModal.inLibrary, "success");
            // Update the related grid immediately to show the "added" badge
            related = related.map((r) =>
                r.id === rel.id ? { ...r, localItem: created } : r,
            );
            previewRelatedItem = null;
            onUpdate();
            onOpenRelated(created);
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
        } finally {
            previewAddingBusy = false;
        }
    }

    async function loadRecommendations(force = false) {
        if (!media) return;
        const cacheKey = `tsundoku_recs_${media.id}`;
        if (force) {
            localStorage.removeItem(cacheKey);
        } else {
            const cachedStr = localStorage.getItem(cacheKey);
            if (cachedStr) {
                try {
                    const cached = JSON.parse(cachedStr);
                    // 30 days = 30 * 24 * 60 * 60 * 1000 = 2592000000 ms
                    if (
                        Date.now() - cached.timestamp < 2592000000 &&
                        Array.isArray(cached.items) &&
                        cached.items.length > 0
                    ) {
                        recommendations = cached.items;
                        return;
                    }
                } catch {}
            }
        }

        recommendationsLoading = true;
        recommendationsError = null;

        try {
            let items: RecommendationItem[] = [];
            if (media.type === "game") {
                try {
                    const gameRecs = await getGameRecommendations({
                        rawgId:
                            media.externalSource?.toLowerCase() === "rawg"
                                ? media.externalId
                                : null,
                        title: media.title,
                        externalSource: media.externalSource,
                        externalId: media.externalId,
                    });
                    items = gameRecs.map((r, idx) => ({
                        id: r.id || `rec-game-${idx}`,
                        title: r.title,
                        coverUrl: r.coverUrl,
                        score: r.score,
                        type: "game",
                    }));
                } catch {}
            } else if (isAnime(media) || media.type === "manga") {
                const query = `
          query ($search: String) {
            Media(search: $search) {
              recommendations(page: 1, perPage: 10, sort: RATING_DESC) {
                nodes {
                  mediaRecommendation {
                    id
                    title { romaji english userPreferred }
                    coverImage { large }
                    averageScore
                    type
                  }
                }
              }
            }
          }
        `;
                const res = await fetch("https://graphql.anilist.co/", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        query,
                        variables: { search: media.title },
                    }),
                });
                if (res.ok) {
                    const json = await res.json();
                    const nodes =
                        json?.data?.Media?.recommendations?.nodes ?? [];
                    items = nodes
                        .filter((n: any) => n?.mediaRecommendation)
                        .map((n: any) => ({
                            id: String(n.mediaRecommendation.id),
                            title:
                                n.mediaRecommendation.title.english ||
                                n.mediaRecommendation.title.romaji ||
                                n.mediaRecommendation.title.userPreferred ||
                                "Title",
                            coverUrl:
                                n.mediaRecommendation.coverImage?.large ?? null,
                            score:
                                typeof n.mediaRecommendation.averageScore ===
                                "number"
                                    ? n.mediaRecommendation.averageScore / 10
                                    : null,
                            type:
                                n.mediaRecommendation.type?.toLowerCase() ===
                                "manga"
                                    ? "manga"
                                    : "anime",
                        }));
                }
            }

            recommendations = items;
            localStorage.setItem(
                cacheKey,
                JSON.stringify({ timestamp: Date.now(), items }),
            );
        } catch (e) {
            recommendationsError = e;
        } finally {
            recommendationsLoading = false;
        }
    }








    function stepProgress(delta: number) {
        const info = progressInfo;
        const target = media;
        if (!info || !info.editable || !target) return;

        const next = clampProgress(progressValue + delta, info.total);
        if (next === progressValue) return;

        if (pendingSnapshot === null) pendingSnapshot = committedProgress;
        progressValue = next;
        progressError = null;
        progressDebounce.schedule(target.id, next);
    }

    async function changeStatus(value: MediaStatus) {
        const target = media;
        if (!target || statusBusy) return;
        if (value === statusValue) return;

        const previous = statusValue;
        statusValue = value;
        statusBusy = true;
        statusError = null;

        try {
            await updateStatus(target.id, value);
            showToast(
                i18n.t.status.label + ": " + statusLabel(value),
                "success",
            );
            onUpdate();
        } catch (error) {
            statusValue = previous;
            statusError = error;
            showToast(errorMessage(error), "error");
        } finally {
            statusBusy = false;
        }
    }

    async function setScore(score: number) {
        const target = media;
        if (!target || ratingBusy) return;

        const next = scoreValue === score ? null : score;
        const previous = scoreValue;
        scoreValue = next;
        ratingBusy = true;
        ratingError = null;

        try {
            await updateMedia(target.id, { score: next });
            showToast(
                next ? `${next} ★` : i18n.t.detail.clearRating,
                "success",
            );
            onUpdate();
        } catch (error) {
            scoreValue = previous;
            ratingError = error;
            showToast(errorMessage(error), "error");
        } finally {
            ratingBusy = false;
        }
    }

    function clearScore() {
        void setScore(scoreValue ?? 0);
    }

    function retry() {
        // Повтор после ошибки = пользователь просит свежие данные, а не запись из кэша.
        void load(mediaId, ++requestSequence, true, true);
    }

    function startEdit() {
        const target = media;
        if (target) onEdit(target);
    }

    async function removeMedia() {
        const target = media;
        if (!target || deleteBusy) return;
        if (!window.confirm(i18n.t.card.confirmDelete(target.title))) return;

        deleteBusy = true;
        deleteError = null;

        try {
            showToast(i18n.t.detailModal.delete, "warning");
            await onDelete(target.id);
            onBack();
        } catch (error) {
            deleteError = error;
            showToast(errorMessage(error), "error");
        } finally {
            deleteBusy = false;
        }
    }

    async function toggleEpisode(number: number) {
        const target = currentSeason;
        if (!target || episodeBusy) return;

        const current = target.currentEpisode ?? 0;
        // If clicking an already watched episode: unwatch it to number - 1
        // If clicking an unwatched episode: mark watched up to number
        const nextVal = number <= current ? number - 1 : number;

        target.currentEpisode = nextVal;
        episodeBusy = target.id;
        progressError = null;
        onUpdate();

        try {
            await setSeasonProgress(target.id, nextVal);
        } catch (error) {
            target.currentEpisode = current;
            onUpdate();
            progressError = error;
            showToast(errorMessage(error), "error");
        } finally {
            episodeBusy = "";
        }
    }

    async function markSeasonComplete() {
        const target = currentSeason;
        if (!target || episodeBusy) return;
        const total = target.totalEpisodes ?? 0;
        if (total <= 0) return;

        const previous = target.currentEpisode ?? 0;
        target.currentEpisode = total;
        episodeBusy = target.id;
        onUpdate();

        try {
            await setSeasonProgress(target.id, total);
            showToast(i18n.t.detail.markSeasonWatched, "success");
        } catch (error) {
            target.currentEpisode = previous;
            onUpdate();
            progressError = error;
            showToast(errorMessage(error), "error");
        } finally {
            episodeBusy = "";
        }
    }

    async function resetSeasonProgress() {
        const target = currentSeason;
        if (!target || episodeBusy) return;

        const previous = target.currentEpisode ?? 0;
        target.currentEpisode = 0;
        episodeBusy = target.id;
        onUpdate();

        try {
            await setSeasonProgress(target.id, 0);
            showToast(i18n.t.detail.resetSeason, "warning");
        } catch (error) {
            target.currentEpisode = previous;
            onUpdate();
            progressError = error;
            showToast(errorMessage(error), "error");
        } finally {
            episodeBusy = "";
        }
    }

    async function handleRefreshMetadata() {
        const target = media;
        if (!target || refreshBusy) return;
        refreshBusy = true;
        refreshError = null;
        try {
            const updated = await refreshMetadata(target.id);
            media = updated;
            syncFrom(updated);
            mediaDetailCache.invalidate(target.id);
            achievementsCache.invalidate(target.id);
            enrichedMediaIds.delete(target.id);
            if (updated.type === "game") {
                void loadGameAchievements(updated, true);
            }
            void loadRelated(updated, true);
            void triggerBackgroundEnrichment(updated, ++requestSequence, true);
            showToast(i18n.t.detail.metadataUpdated, "success");
            onUpdate();
        } catch (error) {
            refreshError = error;
            showToast(errorMessage(error), "error");
        } finally {
            refreshBusy = false;
        }
    }
</script>

<svelte:window
    onkeydown={(e) => {
        if (e.key === "Escape" && previewRelatedItem) previewRelatedItem = null;
    }}
/>

<div class="isolate space-y-6">
    <button
        type="button"
        class="tap inline-flex items-center gap-2 text-sm font-medium text-muted transition hover:text-white"
        onclick={onBack}
    >
        <ArrowLeft size={16} aria-hidden="true" />
        {i18n.t.common.back}
    </button>

    {#if !media && isLoading}
        <div
            class="grid gap-6 lg:grid-cols-[20rem_minmax(0,1fr)]"
            aria-hidden="true"
        >
            <div
                class="aspect-[2/3] w-full animate-pulse rounded-xl bg-card"
            ></div>
            <div class="space-y-4">
                <div class="h-9 w-3/4 animate-pulse rounded bg-card"></div>
                <div class="h-4 w-1/2 animate-pulse rounded bg-card"></div>
                <div class="h-40 animate-pulse rounded-xl bg-card"></div>
            </div>
        </div>
        <p class="sr-only" role="status">{i18n.t.common.loading}</p>
    {:else if !media}
        <div
            class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-xl bg-rose-400/5 p-6 text-center"
        >
            <p class="text-sm text-rose-200" role="alert">
                {loadError ? errorMessage(loadError) : i18n.t.detail.notFound}
            </p>
            {#if loadError}
                <button
                    type="button"
                    class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover"
                    onclick={retry}
                >
                    <RefreshCw size={15} aria-hidden="true" />
                    {i18n.t.common.retry}
                </button>
            {/if}
        </div>
    {:else}
        {@const support = progressInfo}
        <div class="flex flex-col gap-8 lg:flex-row">
            <!-- Left Column: Poster, Status + Rating, History, Actions, Details -->
            <DetailSidebar
                {media}
                {statusOptions}
                {statusBusy}
                onChangeStatus={changeStatus}
                {statusError}
                {scoreValue}
                ratingOpen={userRatingPopoverOpen}
                onRatingOpen={openRatingPopover}
                onRatingClose={closeRatingPopover}
                onRatingHide={hideRatingPopover}
                onSetScore={setScore}
                onClearScore={clearScore}
                {formatDate}
                {historyProgressText}
                {watchedOnInput}
                {watchedOnOptions}
                onWatchedOnInput={(value) => (watchedOnInput = value)}
                onWatchedOnDirty={() => (watchedOnDirty = true)}
                onSaveWatchedOn={saveWatchedOn}
                platformOptions={gamePlatformOptions}
                onSelectPlatform={updateUserPlatform}
                {refreshBusy}
                {refreshError}
                onRefreshMetadata={handleRefreshMetadata}
                onStartEdit={startEdit}
                {deleteBusy}
                {deleteError}
                onDelete={removeMedia}
                {onNavigate}
                specRows={specRows(media)}
            />

            <!-- Right Column: Header, Badges, Tabs, Tab Content -->
            <div class="min-w-0 flex-1 space-y-6">
                <DetailHeader
                    title={media.title}
                    {originalTitle}
                    tags={tags(media)}
                    ratings={externalRatings}
                    {sourceBadgeClasses}
                    synopsisText={synopsisText}
                    {synopsisExpanded}
                    {synopsisExpandable}
                    synopsisTranslated={isSynopsisTranslated}
                    {translatedSynopsis}
                    {translatingSynopsis}
                    onToggleTranslate={toggleTranslateSynopsis}
                    onToggleExpand={() => (synopsisExpanded = !synopsisExpanded)}
                />
<!-- Sub-navigation tabs -->
<DetailTabs
    active={activeSubTab}
    mediaType={media.type}
    seasonProgress={currentSeason
        ? {
            current: currentSeason.currentEpisode ?? 0,
            total: currentSeason.totalEpisodes ?? null,
        }
        : null}
    volumeCount={mangaVolumes.length}
    relatedCount={related.length}
    onSelect={(tab) => (activeSubTab = tab)}
/>

                <!-- TAB 1: OVERVIEW -->
                {#if activeSubTab === "overview"}
                    <div class="space-y-6">

                        <!-- Game Circular Counter / Book & Manga Stepper Progress -->
                        {#if media.type === "game"}
                            <GameDetailSection
                                {progressValue}
                                progressLabel={support?.label ??
                                    i18n.t.detail.hoursLabel}
                                {progressError}
                                onCounterChange={(val) => {
                                    if (!media) return;
                                    const next = Math.max(val, 0);
                                    if (pendingSnapshot === null)
                                        pendingSnapshot = committedProgress;
                                    progressValue = next;
                                    progressError = null;
                                    progressDebounce.schedule(
                                        media.id,
                                        next,
                                    );
                                }}
                                achievements={gameAchievements}
                                achievementsTotal={gameAchievementsTotal}
                                achievementsLoading={gameAchievementsLoading}
                                {achievementsBusy}
                                {achievementsTruncated}
                                unlockedNames={unlockedAchievementNames}
                                onToggleAchievement={toggleAchievement}
                                onToggleAllAchievements={toggleAllAchievements}
                            />
{:else if support && support.editable}
    <ProgressStepper
        progress={support}
        value={progressValue}
        percent={progressPercent}
        error={progressError}
        onStep={stepProgress}
    />
                        {/if}

                        <!-- Manga Volumes Section on Overview (Item 6) -->
                        {#if media.type === "manga"}
                            <MangaDetailSection
                                {media}
                                volumes={mangaVolumes}
                                volumeBusy={volumes.busy}
                                isDone={isVolumeDone}
                                current={volumeCurrent}
                                total={volumeTotal}
                                percent={volumePercent}
                                progressLabel={volumeProgressLabel}
                                onStepPage={(vol, delta) =>
                                    void volumes.stepVolume(vol, delta)}
                                onEdit={(vol) => volumes.openEdit(vol)}
                                onDelete={(vol) => void volumes.remove(vol)}
                                onMarkComplete={(vol) =>
                                    void volumes.markComplete(vol)}
                                onUnmarkComplete={(vol) =>
                                    void volumes.unmarkComplete(vol)}
                                onAddVolume={() => volumes.openAdd()}
                                onGenerateVolumes={() =>
                                    void volumes.generateMissing()}
                                onOpenVolumesTab={() =>
                                    (activeSubTab = "volumes")}
                            />
                        {/if}
                    </div>
                {/if}

                <!-- TAB 2: EPISODES (Items 1, 3, 4, 12) -->
                {#if media.type === "tvshow"}
                    <TvShowDetailSection
                        {seasons}
                        {currentSeason}
                        showEpisodes={activeSubTab === "episodes"}
                        {sortedEpisodes}
                        {nextEpisode}
                        {seasonProgressPercent}
                        {episodeBusy}
                        {progressError}
                        sortOrder={episodeSortOrder}
                        onSelectSeason={(id) => (selectedSeasonId = id)}
                        onToggleSort={() =>
                            (episodeSortOrder =
                                episodeSortOrder === "asc" ? "desc" : "asc")}
                        onMarkSeasonComplete={markSeasonComplete}
                        onResetSeason={resetSeasonProgress}
                        onToggleEpisode={toggleEpisode}
                        onOpenEpisodesTab={() => (activeSubTab = "episodes")}
                        onOpenLists={() => onNavigate("lists")}
                        {formatDate}
                    />
                {/if}

                <!-- TAB: MANGA VOLUMES -->
{#if activeSubTab === "volumes" && media.type === "manga"}
    <VolumesPanel
        {media}
        volumes={mangaVolumes}
        busy={volumes.busy}
        onAdd={() => volumes.openAdd()}
        onGenerate={() => void volumes.generateMissing()}
        onStep={(vol, delta) => void volumes.stepVolume(vol, delta)}
        onEdit={(vol) => volumes.openEdit(vol)}
        onDelete={(vol) => void volumes.remove(vol)}
        onMarkComplete={(vol) => void volumes.markComplete(vol)}
        onUnmarkComplete={(vol) => void volumes.unmarkComplete(vol)}
    />
{/if}

<!-- TAB 3: RELATED MEDIA -->
{#if activeSubTab === "related"}
    <RelatedPanel
        {related}
        loading={relatedLoading}
        error={relatedError}
        viewMode={relatedViewMode}
        groups={relatedGroups}
        timeline={timelineEntries}
        onRetry={() => {
            if (media) void loadRelated(media, true);
        }}
        onSelectViewMode={(mode) => (relatedViewMode = mode)}
        onOpen={handleRelatedClick}
    />
{/if}

<!-- PREVIEW MODAL FOR UNADDED RELATED ITEMS -->
<RelatedPreviewModal
    item={previewRelatedItem}
    badges={previewRelatedBadges}
    loading={previewRelatedLoading}
    adding={previewAddingBusy}
    status={previewStatus}
    onStatusChange={(v) => (previewStatus = v)}
    onAdd={(status) => {
        if (previewRelatedItem)
            void addRelatedToLibrary(previewRelatedItem, status);
    }}
    onClose={() => (previewRelatedItem = null)}
/>

<!-- TAB 4: RECOMMENDATIONS -->
{#if activeSubTab === "recommendations"}
    <RecommendationsPanel
        items={recommendations}
        loading={recommendationsLoading}
        error={recommendationsError}
        onLoad={(force) => void loadRecommendations(force)}
    />
{/if}

            </div>
        </div>
    {/if}
</div>

<!-- Add / edit volume dialogs -->
<VolumeFormModal
    mode="add"
    open={volumes.addDialogOpen}
    busy={Boolean(volumes.busy)}
    title={volumes.addTitle}
    chapters={volumes.addChapters}
    onTitleChange={(v) => (volumes.addTitle = v)}
    onChaptersChange={(v) => (volumes.addChapters = v)}
    onClose={volumes.closeAdd}
    onSubmit={() => void volumes.confirmAdd()}
/>

<VolumeFormModal
    mode="edit"
    open={volumes.editDialogOpen}
    busy={Boolean(volumes.busy)}
    title={volumes.editTitle}
    chapters={volumes.editChapters}
    pages={volumes.editPages}
    currentChapter={volumes.editCurrentChapter}
    currentPage={volumes.editCurrentPage}
    onTitleChange={(v) => (volumes.editTitle = v)}
    onChaptersChange={(v) => (volumes.editChapters = v)}
    onPagesChange={(v) => (volumes.editPages = v)}
    onCurrentChapterChange={(v) => (volumes.editCurrentChapter = v)}
    onCurrentPageChange={(v) => (volumes.editCurrentPage = v)}
    onClose={volumes.closeEdit}
    onSubmit={() => void volumes.confirmEdit()}
/>
