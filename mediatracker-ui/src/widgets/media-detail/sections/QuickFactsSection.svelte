<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaDetail } from "$shared/types";

    let { media }: { media: MediaDetail } = $props();

    const typeLabel = $derived.by(() => {
        if (media.type === "game") return i18n.t.detail.formatGame;
        if (media.type === "book") return i18n.t.detail.formatBook;
        if (media.type === "manga") return i18n.t.detail.formatManga;
        if ((media.type === "movie" || media.type === "tvshow") && media.isAnime) return i18n.t.detail.formatAnime;
        return media.type === "movie" ? i18n.t.detail.formatMovie : i18n.t.detail.formatSeries;
    });

    function counted(count: number, enSingular: string, enPlural: string, ruSingular: string, ruFew: string, ruMany: string) {
        if (i18n.current === "en") return `${count} ${count === 1 ? enSingular : enPlural}`;
        const lastTwo = count % 100;
        const last = count % 10;
        const word = lastTwo >= 11 && lastTwo <= 14 ? ruMany : last === 1 ? ruSingular : last >= 2 && last <= 4 ? ruFew : ruMany;
        return `${count} ${word}`;
    }

    const statusLabel = $derived.by(() => {
        const status = media.releaseStatus?.replaceAll("_", " ").trim().toLowerCase();
        if (!status) return null;
        if (["releasing", "returning series", "ongoing"].includes(status)) return i18n.t.detail.statusOngoing;
        if (["finished", "ended", "released"].includes(status)) return i18n.t.detail.statusFinished;
        if (["not yet released", "planned", "announced", "upcoming"].includes(status)) return i18n.t.detail.statusAnnounced;
        return media.releaseStatus;
    });

    const measure = $derived.by(() => {
        if (media.type === "movie" && media.durationMinutes > 0) return `${media.durationMinutes} ${i18n.t.detail.minShort}`;
        if (media.type === "tvshow" && media.durationMinutes && media.durationMinutes > 0) return `${media.durationMinutes} ${i18n.t.detail.minPerEp}`;
        if (media.type === "book" && media.totalPages > 0) return counted(media.totalPages, "page", "pages", "страница", "страницы", "страниц");
        if (media.type === "manga") {
            const parts = [
                media.totalVolumes && counted(media.totalVolumes, "volume", "volumes", "том", "тома", "томов"),
                media.totalChapters && counted(media.totalChapters, "chapter", "chapters", "глава", "главы", "глав"),
            ].filter(Boolean);
            return parts.join(" · ") || null;
        }
        if (media.type === "tvshow" && media.totalEpisodesCount > 0) return counted(media.totalEpisodesCount, "episode", "episodes", "серия", "серии", "серий");
        if (media.type === "game" && media.hoursPlayed) return counted(media.hoursPlayed, "hour", "hours", "час", "часа", "часов");
        return null;
    });

    const language = $derived.by(() => {
        const value = media.originalLanguage?.trim();
        if (!value) return null;
        const code = value.toLowerCase();
        const name = ({ en: "English", ja: "Japanese", ko: "Korean", zh: "Chinese", ru: "Russian", fr: "French", es: "Spanish", de: "German", it: "Italian", pt: "Portuguese" } as Record<string, string>)[code]
            ?? new Intl.DisplayNames([i18n.current], { type: "language" }).of(code)
            ?? value;
        const flag = ({ en: "🇺🇸", ja: "🇯🇵", ko: "🇰🇷", zh: "🇨🇳", ru: "🇷🇺", fr: "🇫🇷", es: "🇪🇸", de: "🇩🇪", it: "🇮🇹", pt: "🇵🇹" } as Record<string, string>)[code];
        return `${flag ? `${flag} ` : ""}${name}`;
    });

    const country = $derived.by(() => {
        const value = media.countryOfOrigin?.trim().toUpperCase();
        if (!value) return null;
        const name = new Intl.DisplayNames([i18n.current], { type: "region" }).of(value) ?? value;
        const flag = value.length === 2 ? String.fromCodePoint(...[...value].map(char => 127397 + char.charCodeAt(0))) : "";
        return `${flag} ${name}`;
    });
</script>

<section class="space-y-2">
    <h2 class="text-xs font-semibold uppercase tracking-[0.14em] text-muted">{i18n.t.detail.quickFacts}</h2>
    <div class="flex flex-wrap gap-2">
        <span class="rounded-lg border border-white/5 bg-surface/60 px-3 py-1.5 text-xs text-muted">{typeLabel}</span>
        {#if language}<span class="rounded-lg border border-white/5 bg-surface/60 px-3 py-1.5 text-xs text-muted">{language}</span>{/if}
        {#if country}<span class="rounded-lg border border-white/5 bg-surface/60 px-3 py-1.5 text-xs text-muted">{country}</span>{/if}
        {#if statusLabel}<span class="rounded-lg border border-white/5 bg-surface/60 px-3 py-1.5 text-xs text-muted">{statusLabel}</span>{/if}
        {#if measure}<span class="rounded-lg border border-white/5 bg-surface/60 px-3 py-1.5 text-xs text-muted">{measure}</span>{/if}
    </div>
</section>
