import { i18n } from "$shared/i18n/index.svelte";
import {
    isMangaDetail,
    isTvShowDetail,
    type MediaItem,
    type MediaStatus,
    type TvSeason,
} from "$shared/types";
import { statusLabel } from "$entities/media/model/mediaLabels";
import type { EpisodeRow, ProgressInfo, SpecRow } from "./detailTypes";

/**
 * Season rows are synthesised from a count because most seasons arrive without an
 * episodesData payload. Capped so a bogus "5000 episodes" metadata value cannot
 * render 5000 rows.
 */
export const maxEpisodesPerSeason = 200;

export function isAnime(item: MediaItem): boolean {
    return (
        (item.type === "tvshow" || item.type === "movie") && Boolean(item.isAnime)
    );
}

export function typeLabel(item: MediaItem): string {
    return isAnime(item) ? i18n.t.navigation.anime : i18n.t.types[item.type];
}

/**
 * Manga is stored as one type, but the origin decides how it is read: a manhwa or an OEL title
 * called just "Манга" is wrong. Falls back to the plain type label when no source knew.
 */
export function formatLabel(item: MediaItem): string {
    if (!isMangaDetail(item)) return typeLabel(item);

    const known = item.mangaFormat;
    if (!known) return typeLabel(item);

    const labels = i18n.t.detail.mangaFormats as Record<string, string>;
    return labels[known] ?? typeLabel(item);
}

export { statusLabel };

export function dataSource(item: MediaItem): string {
    if (item.externalSource) return item.externalSource;
    if (isAnime(item) || item.type === "manga") return "AniList";

    switch (item.type) {
        case "game":
            return "RAWG";
        case "book":
            return "OpenLibrary";
        default:
            return "TMDB";
    }
}

/**
 * The external page of an item, built from the source that actually supplied it.
 *
 * This used to return a bare domain and fall through to `anilist.co` for anything unrecognised, so a
 * Dune matched by Kinopoisk linked to AniList with an AniList-styled id. The URL is now composed per
 * source and an unknown source yields no link at all rather than a wrong one.
 */
export function providerLink(item: MediaItem): { name: string; url: string } | null {
    const src = (item.externalSource || dataSource(item)).toLowerCase();
    const id = (item.externalId ?? "").trim();

    if (src.includes("kinopoisk")) {
        return id ? { name: "Кинопоиск", url: `https://www.kinopoisk.ru/film/${encodeURIComponent(id)}/` } : null;
    }
    if (src.includes("tmdb") || src.includes("movie database")) {
        if (!id) return null;
        const kind = item.type === "tvshow" || isAnime(item) ? "tv" : "movie";
        return { name: "TMDb", url: `https://www.themoviedb.org/${kind}/${encodeURIComponent(id)}` };
    }
    if (src.includes("rawg")) {
        // RAWG ids are numeric, but the site's own slug is what the page path expects; the search
        // link works with either, so a slug-less id still gets a usable target.
        return {
            name: "RAWG",
            url: id
                ? `https://rawg.io/games/${encodeURIComponent(slugify(item.title))}-${encodeURIComponent(id)}`
                : `https://rawg.io/search?q=${encodeURIComponent(item.title)}`,
        };
    }
    if (src.includes("mangadex")) {
        return id ? { name: "MangaDex", url: `https://mangadex.org/title/${encodeURIComponent(id)}` } : null;
    }
    if (src.includes("anilist")) {
        if (!id) return null;
        const kind = item.type === "manga" ? "manga" : "anime";
        return { name: "AniList", url: `https://anilist.co/${kind}/${encodeURIComponent(id)}` };
    }
    if (src.includes("mal") || src.includes("jikan") || src.includes("myanimelist")) {
        return {
            name: "MyAnimeList",
            url: id ? `https://myanimelist.net/anime/${encodeURIComponent(id)}` : "https://myanimelist.net",
        };
    }
    if (src.includes("openlibrary")) {
        return {
            name: "OpenLibrary",
            url: `https://openlibrary.org${id.startsWith("/") ? id : `/${id}`}`,
        };
    }
    if (src.includes("igdb")) {
        return id ? { name: "IGDB", url: `https://www.igdb.com/games/${encodeURIComponent(slugify(item.title))}` } : null;
    }
    if (src.includes("steam")) {
        return id ? { name: "Steam", url: `https://store.steampowered.com/app/${encodeURIComponent(id)}` } : null;
    }
    return null;
}

/** Lowercase hyphenated form RAWG and IGDB use in their URLs. */
function slugify(title: string): string {
    return title
        .toLowerCase()
        .normalize("NFKD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "");
}

export function tags(item: MediaItem): string[] {
    const list: string[] = [typeLabel(item)];

    switch (item.type) {
        case "game":
            // The header shows the platform the user picked in Ваша история;
            // the full release list lives in the platform dropdown instead.
            if (item.userPlatform?.trim()) list.push(item.userPlatform.trim());
            else if (item.platform) list.push(item.platform);
            break;
        case "book":
        case "manga":
            if (item.author) list.push(item.author);
            break;
        case "movie":
            if (item.studio) list.push(item.studio);
            if (item.director) list.push(item.director);
            break;
        case "tvshow":
            if (item.studio) list.push(item.studio);
            if (item.network) list.push(item.network);
            break;
    }

    return [...new Set(list.filter(Boolean))];
}

export function releaseStatusLabel(item: MediaItem): string {
    const raw = item.releaseStatus?.trim().toUpperCase();
    const r = i18n.t.detail.releaseStatuses;

    if (item.type === "game") {
        const isRu = i18n.current === "ru";
        const comingSoon = isRu ? "Скоро выйдет" : "Coming Soon";
        const earlyAccess = isRu ? "Ранний доступ" : "Early Access";
        const fullRelease = isRu ? "Релиз" : "Full Release";

        if (raw) {
            if (
                raw.includes("COMING") ||
                raw.includes("NOT_YET") ||
                raw.includes("UPCOMING") ||
                raw.includes("СКОРО")
            )
                return comingSoon;
            if (raw.includes("EARLY") || raw.includes("РАННИЙ"))
                return earlyAccess;
            if (
                raw.includes("FULL") ||
                raw.includes("RELEASE") ||
                raw.includes("FINISHED") ||
                raw.includes("COMPLETED") ||
                raw.includes("РЕЛИЗ")
            )
                return fullRelease;
        }
        if (item.releaseDate) {
            const start = new Date(item.releaseDate);
            if (!Number.isNaN(start.getTime()) && start > new Date())
                return comingSoon;
        }
        return fullRelease;
    }

    if (raw) {
        if (
            raw === "RELEASING" ||
            raw === "CURRENT" ||
            raw === "RETURNING SERIES"
        )
            return r.releasing;
        if (raw === "FINISHED" || raw === "COMPLETED" || raw === "ENDED")
            return r.finished;
        if (
            raw === "NOT_YET_RELEASED" ||
            raw === "UPCOMING" ||
            raw === "IN PRODUCTION"
        )
            return r.notYetReleased;
        if (raw === "CANCELLED" || raw === "CANCELED") return r.cancelled;
        if (raw === "HIATUS" || raw === "ON HIATUS") return r.hiatus;
    }

    // Fallback: calculate from dates if no API status
    const now = new Date();
    now.setHours(0, 0, 0, 0);

    if (item.endDate) {
        const end = new Date(item.endDate);
        if (!Number.isNaN(end.getTime()) && end <= now) return r.finished;
    }

    if (item.releaseDate) {
        const start = new Date(item.releaseDate);
        if (!Number.isNaN(start.getTime())) {
            if (start > now) return r.notYetReleased;
            return r.releasing;
        }
    }

    return i18n.t.detailModal.valueEmpty;
}

/**
 * Chapters for the detail screen, read from the same `totalChapters` the card renders.
 *
 * This used to prefer the volume sum whenever the volumes carried chapter counts, which made
 * "Характеристики" show one number while the card next to it showed another for the same title.
 * The counter is reconciled from the volumes on refresh, so one field is the single source.
 */
export function mangaChapterProgress(item: MediaItem): {
    current: number;
    total: number | null;
} {
    if (item.type !== "manga") return { current: 0, total: null };
    return { current: item.currentChapter, total: item.totalChapters };
}

export function readProgress(item: MediaItem): ProgressInfo | null {
    switch (item.type) {
        case "game":
            return {
                current: item.hoursPlayed ?? 0,
                total: null,
                editable: true,
                label: i18n.t.detail.hoursLabel,
            };
        case "book":
            return {
                current: item.currentPage,
                total: item.totalPages,
                editable: true,
                label: i18n.t.detail.pagesLabel,
            };
        case "manga": {
            const chapters = mangaChapterProgress(item);
            return {
                current: chapters.current,
                total: chapters.total,
                editable: true,
                label: i18n.t.detail.chaptersLabel,
            };
        }
        case "tvshow":
            return {
                current: item.totalEpisodesWatched,
                total: item.totalEpisodesCount,
                editable: false,
                label: i18n.t.detail.episodesLabel,
            };
        default:
            return null;
    }
}

export function readOriginalTitle(item: MediaItem): string | null {
    if (item.type === "tvshow" || item.type === "movie") {
        const value = item.romajiTitle?.trim();
        return value ? value : null;
    }
    return null;
}

/** The transliterated title, for every type that stores one. Game and book have none. */
export function readRomajiTitle(item: MediaItem): string | null {
    if (item.type === "game" || item.type === "book") return null;
    const value = item.romajiTitle?.trim();
    return value ? value : null;
}

export function formatDate(value: string | null): string {
    if (!value) return i18n.t.detailModal.dateEmpty;
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime())
        ? i18n.t.detailModal.dateEmpty
        : new Intl.DateTimeFormat(i18n.current, { dateStyle: "medium" }).format(
              parsed,
          );
}

/**
 * Renders only the precision the source actually provided. A source that knows just the year
 * must not be padded into "1 January", so the stored releaseYear carries the fallback.
 *
 * The end date is a different case: a missing end date means "still running", so it must never
 * borrow the start date's year. That is why the year fallback only applies to the start row.
 */
export function formatReleaseDate(
    item: MediaItem,
    explicitDate?: string | null,
): string {
    const isEndDate = explicitDate !== undefined;
    const raw = isEndDate ? explicitDate : item.releaseDate;

    if (raw) return formatDate(raw);
    if (isEndDate) return i18n.t.detailModal.dateEmpty;

    const year = item.releaseYear;
    if (year && year > 0) {
        return i18n.current === "ru" ? `${year} год` : `${year}`;
    }
    return i18n.t.detailModal.dateEmpty;
}

export function orderOf(item: MediaItem): number {
    return item.franchiseOrder ?? Number.MAX_SAFE_INTEGER;
}

export function buildEpisodes(value: TvSeason): EpisodeRow[] {
    let parsed: Array<{
        number: number;
        title?: string;
        airDate?: string;
        description?: string;
    }> = [];
    if (value.episodesData) {
        try {
            parsed = JSON.parse(value.episodesData);
        } catch {}
    }
    const total = Math.max(value.totalEpisodes ?? 0, parsed.length, 0);
    const watched = Math.max(value.currentEpisode ?? 0, 0);
    const limit = Math.min(total, Math.max(watched, maxEpisodesPerSeason));

    return Array.from({ length: limit }, (_, index) => {
        const number = index + 1;
        const found = parsed.find((p) => p.number === number);
        return {
            id: `${value.id}:${number}`,
            number,
            title: found?.title || i18n.t.detail.episodeTitle(number),
            airDate: found?.airDate ?? value.airDate ?? null,
            description: found?.description ?? value.notes ?? null,
            watched: number <= watched,
        };
    });
}

/**
 * Status circle colours for the related grid/timeline. Deliberately separate from
 * mediaLabels.statusBadgeClasses, which styles the pill badges on library cards.
 */
export function relatedStatusClasses(status: MediaStatus): string {
    switch (status) {
        case 2:
            return "bg-[var(--color-brand-green)] text-white border-2 border-[color-mix(in_oklab,var(--color-success-soft)_80%,transparent)] ring-2 ring-[color-mix(in_oklab,var(--color-success-soft)_30%,transparent)]";
        case 1:
            return "bg-[var(--color-brand-blue)] text-white border-2 border-[color-mix(in_oklab,var(--color-ink-faint)_80%,transparent)] ring-2 ring-[color-mix(in_oklab,var(--color-ink-faint)_30%,transparent)]";
        case 3:
            return "bg-[var(--color-warning-line)] text-white border-2 border-amber-300/80 ring-2 ring-amber-300/30";
        case 4:
            return "bg-[var(--color-danger-line)] text-white border-2 border-rose-300/80 ring-2 ring-rose-300/30";
        default:
            return "bg-[var(--color-track)] text-slate-100 border-2 border-slate-400/70 ring-2 ring-slate-400/20";
    }
}

/** Relation label for a related entry, falling back to its media format. */
export function formatMediaDisplayType(rel: {
    type: string;
    format?: string | null;
}): string {
    if (rel.type === "game") return i18n.current === "ru" ? "Игра" : "Game";
    if (rel.type === "book") return i18n.current === "ru" ? "Книга" : "Book";
    const f = rel.format?.toUpperCase();
    const fmt = i18n.t.detail.formats;
    if (f === "MOVIE") return fmt.movie;
    if (f === "TV" || f === "TV_SHORT") return fmt.tv;
    if (f === "OVA") return fmt.ova;
    if (f === "ONA") return fmt.ona;
    if (f === "SPECIAL") return fmt.special;
    if (f === "MANGA") return fmt.manga;
    if (f === "NOVEL") return fmt.novel;
    if (f === "ONE_SHOT") return fmt.oneShot;
    if (f === "MUSIC") return fmt.music;
    return rel.type === "manga"
        ? fmt.manga
        : rel.type === "movie"
          ? fmt.movie
          : fmt.tv;
}

export function formatRelationType(relType?: string): string {
    const r = i18n.t.detail.relations;
    switch (relType) {
        case "SEQUEL":
            return r.sequel;
        case "PREQUEL":
            return r.prequel;
        case "ADAPTATION":
            return r.adaptation;
        case "SIDE_STORY":
            return r.sideStory;
        case "SPIN_OFF":
            return r.spinOff;
        case "SUMMARY":
            return r.summary;
        case "ALTERNATIVE":
            return r.alternative;
        case "CHARACTER":
            return r.character;
        default:
            return r.other;
    }
}

export function currentFormatLabel(item: MediaItem): string {
    return isTvShowDetail(item)
        ? i18n.t.detail.formats.tv
        : item.type === "movie"
          ? i18n.t.detail.formats.movie
          : item.type === "manga"
            ? i18n.t.detail.formats.manga
            : item.type;
}

/**
 * A film or book whose release date has already passed. Sources keep reporting "releasing" for
 * titles that shipped years ago, which is what put an "Онгоинг" badge on a finished Dune.
 */
function hasAlreadyReleased(item: MediaItem): boolean {
    if (item.releaseDate) {
        return new Date(item.releaseDate).getTime() <= Date.now();
    }
    return item.releaseYear != null && item.releaseYear <= new Date().getFullYear();
}

function parseGenresList(genres?: string[] | string | null): string[] {
    if (!genres) return [];
    if (Array.isArray(genres)) return genres.map((g) => g.trim()).filter(Boolean);
    if (typeof genres === "string") {
        const trimmed = genres.trim();
        if (!trimmed) return [];
        if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
            try {
                const parsed = JSON.parse(trimmed);
                if (Array.isArray(parsed)) {
                    return parsed.map((g: unknown) => String(g).trim()).filter(Boolean);
                }
            } catch {}
        }
        return trimmed.split(",").map((g) => g.trim()).filter(Boolean);
    }
    return [];
}

export function specRows(item: MediaItem): SpecRow[] {
    const empty = i18n.t.detailModal.valueEmpty;
    const rows: SpecRow[] = [
        { label: i18n.t.detail.formatLabel, value: formatLabel(item) },
    ];

    if (item.type === "game") {
        rows.push({
            label: i18n.current === "ru" ? "Дата релиза" : "Release date",
            value: formatReleaseDate(item),
        });
        rows.push({
            label: i18n.t.status.label,
            value: releaseStatusLabel(item),
        });
        const t = item.tags
            ? (Array.isArray(item.tags)
                  ? item.tags.join(", ")
                  : item.tags
              ).trim()
            : "";
        rows.push({
            label: i18n.current === "ru" ? "Теги" : "Tags",
            value: t || "—",
        });
    } else if (item.type === "movie" || item.type === "book") {
        // A film and a book are released once: the "start / end" pair was a series-shaped row pair
        // shown on items that cannot have an end, so one row reads as an unfinished run.
        rows.push({
            label:
                item.type === "movie"
                    ? i18n.current === "ru"
                        ? "Дата релиза"
                        : "Release date"
                    : i18n.current === "ru"
                      ? "Дата публикации"
                      : "Publication date",
            value: formatReleaseDate(item),
        });

        // "Онгоинг" on a released film or book is the source's stale status, not the user's state.
        const isOngoing =
            item.releaseStatus === "RELEASING" || item.releaseStatus === "releasing";
        if (!isOngoing || !hasAlreadyReleased(item)) {
            rows.push({
                label: i18n.t.status.label,
                value: releaseStatusLabel(item),
            });
        }
    } else {
        rows.push({
            label: i18n.t.detail.startDateLabel,
            value: formatReleaseDate(item),
        });
        rows.push({
            label: i18n.t.detail.endDateLabel,
            value: formatReleaseDate(item, item.endDate),
        });
        rows.push({
            label: i18n.t.status.label,
            value: releaseStatusLabel(item),
        });
    }

    switch (item.type) {
        case "tvshow":
            rows.push({
                label: i18n.t.detail.episodesLabel,
                value: i18n.t.card.episodes(
                    item.totalEpisodesWatched,
                    item.totalEpisodesCount,
                ),
            });
            break;
        case "book":
            rows.push({
                label: i18n.t.detail.pagesLabel,
                value: i18n.t.card.pages(item.currentPage, item.totalPages),
            });
            break;
        case "manga": {
            const chapters = mangaChapterProgress(item);
            rows.push({
                label: i18n.t.detail.chaptersLabel,
                value: i18n.t.card.chapters(chapters.current, chapters.total),
            });

            const vols = (item as { volumes?: unknown }).volumes;
            const totalVols =
                typeof vols === "number"
                    ? vols
                    : (item.totalVolumes ?? (Array.isArray(vols) ? vols.length : null));
            rows.push({
                label: i18n.t.detail.volumesLabel,
                value: totalVols && totalVols > 0 ? `${totalVols}` : "—",
            });
            break;
        }
        case "game":
            // Hours played removed from specRows, stays only in "Ваша история"
            break;
    }

    if (item.type === "movie" || item.type === "tvshow") {
        const duration =
            item.durationMinutes && item.durationMinutes > 0
                ? item.type === "movie"
                    ? i18n.t.card.movie(item.durationMinutes)
                    : `${item.durationMinutes} ${i18n.t.detail.minPerEp}`
                : empty;
        rows.push({ label: i18n.t.detail.durationLabel, value: duration });
    }

    switch (item.type) {
        case "tvshow":
        case "movie":
            rows.push({
                label: i18n.t.detailModal.studio,
                value: item.studio || empty,
            });
            // A romaji title only means something for anime; a live-action show or film has an
            // original title, not a romanized one, so showing the row there is just noise.
            if (isAnime(item) && item.romajiTitle) {
                rows.push({
                    label: i18n.t.detail.romajiTitle,
                    value: item.romajiTitle,
                });
            }
            break;
        case "book":
        case "manga":
            rows.push({
                label: i18n.t.detailModal.author,
                value: item.author || empty,
            });
            // A romaji title only means something for anime; see the comment above.
            if (item.type === "manga" && item.romajiTitle) {
                rows.push({
                    label: i18n.t.detail.romajiTitle,
                    value: item.romajiTitle,
                });
            }
            break;
        case "game":
            rows.push({
                label: i18n.t.detailModal.platform,
                value: item.platform || empty,
            });
            break;
    }

    const genreList = parseGenresList(item.genres);
    rows.push({
        label: i18n.t.detail.genresLabel,
        value: genreList.length > 0 ? genreList.join(", ") : "—",
        badges: genreList.length > 0 ? genreList : undefined,
    });

    rows.push({ label: i18n.t.detail.source, value: dataSource(item) });

    // The link row only appears when the source is one we can actually build a URL for, so the
    // sidebar can never offer a link that leads somewhere else entirely.
    const link = providerLink(item);
    if (link) {
        rows.push({
            label: i18n.t.detail.providerLabel,
            value: link.name,
            href: link.url,
        });
    }

    return rows;
}
