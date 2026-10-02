import { i18n } from "$lib/i18n/index.svelte";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$lib/types";

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