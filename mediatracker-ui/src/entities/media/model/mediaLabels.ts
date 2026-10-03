import { i18n } from "$shared/i18n/index.svelte";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$shared/types";

export function statusLabel(status: MediaStatus): string {
    switch (status) {
        case 0:
            return i18n.t.status.planned;
        case 1:
            return i18n.t.status.inProgress;
        case 2:
            return i18n.t.status.completed;
        case 3:
            return i18n.t.status.paused;
        case 4:
            return i18n.t.status.dropped;
    }
}

export function statusBadgeClasses(status: MediaStatus): string {
    switch (status) {
        case MEDIA_STATUS.inProgress:
            return "border-[#5844e0]/50 bg-[#5844e0]/30 text-[#a5b4fc]";
        case MEDIA_STATUS.completed:
            return "border-emerald-700/50 bg-emerald-950/80 text-emerald-300";
        case MEDIA_STATUS.onHold:
            return "border-amber-700/50 bg-amber-950/80 text-amber-300";
        case MEDIA_STATUS.dropped:
            return "border-rose-700/50 bg-rose-950/80 text-rose-300";
        default:
            return "border-zinc-700/50 bg-zinc-800/80 text-zinc-300";
    }
}

export function cardTypeLabel(media: MediaItem): string {
    if (media.type === "tvshow" && media.isAnime) {
        return i18n.t.navigation.anime;
    }
    return i18n.t.types[media.type];
}

export function formatNumber(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value);
}

export function titleTooltip(title: string): string {
    return title.length > 100 ? title.slice(0, 97) + "..." : title;
}

/**
 * Per-source badge colours. Lives here because three views show them: the library
 * detail header, its sidebar rows and the search preview.
 */
export function sourceBadgeClasses(src: string): string {
    const source = src.toLowerCase();
    if (source.includes("anilist"))
        return "border-[#02a9ff]/30 bg-[#02a9ff]/15 text-[#02a9ff]";
    if (source.includes("shikimori"))
        return "border-[#2e51a2]/40 bg-[#2e51a2]/20 text-[#688ce4]";
    if (source.includes("mangadex"))
        return "border-[#ff6740]/30 bg-[#ff6740]/15 text-[#ff6740]";
    if (
        source.includes("myanimelist") ||
        source.includes("jikan") ||
        source.includes("mal")
    )
        return "border-[#2e51a2]/40 bg-[#2e51a2]/20 text-[#7d9bf0]";
    if (source.includes("tmdb"))
        return "border-[#01b4e4]/30 bg-[#01b4e4]/15 text-[#31c3ef]";
    if (source.includes("rawg"))
        return "border-[#f65e22]/30 bg-[#f65e22]/15 text-[#f79069]";
    if (source.includes("steam"))
        return "border-[#1b2838]/60 bg-[#1b2838]/70 text-[#66c0f4]";
    if (source.includes("igdb"))
        return "border-[#9146ff]/30 bg-[#9146ff]/15 text-[#b18cff]";
    if (source.includes("kitsu"))
        return "border-[#fd755c]/30 bg-[#fd755c]/15 text-[#ff9a86]";
    if (source.includes("simkl"))
        return "border-white/[0.14] bg-black/50 text-white";
    if (source.includes("imdb"))
        return "border-[#f5c518]/30 bg-[#f5c518]/15 text-[#f5c518]";
    if (source.includes("thetvdb") || source.includes("tvdb"))
        return "border-[#42b883]/30 bg-[#42b883]/15 text-[#5cc79a]";
    if (source.includes("mangaupdate"))
        return "border-[#3b82f6]/30 bg-[#3b82f6]/15 text-[#60a5fa]";
    if (source.includes("openlibrary"))
        return "border-[#e1d9cb]/25 bg-[#e1d9cb]/10 text-[#e1d9cb]";
    return "border-white/[0.12] bg-[var(--color-panel-line)] text-amber-400";
}