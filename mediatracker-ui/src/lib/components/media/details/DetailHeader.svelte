<script lang="ts">
    import ChevronDown from "lucide-svelte/icons/chevron-down";
    import Languages from "lucide-svelte/icons/languages";
    import Star from "lucide-svelte/icons/star";
    import { i18n } from "$lib/i18n/index.svelte";

    export interface RatingBadge {
        source: string;
        score: number | null;
        votes?: number | null;
    }

    interface Props {
        title: string;
        /** Romaji / original title; null for types that do not carry one. */
        originalTitle: string | null;
        tags: readonly string[];
        ratings: readonly RatingBadge[];
        sourceBadgeClasses: (source: string) => string;
        synopsisText: string | null;
        synopsisExpanded: boolean;
        synopsisExpandable: boolean;
        synopsisTranslated: boolean;
        translatedSynopsis: string | null;
        translatingSynopsis: boolean;
        onToggleTranslate: () => void;
        onToggleExpand: () => void;
    }

    let {
        title,
        originalTitle,
        tags,
        ratings,
        sourceBadgeClasses,
        synopsisText,
        synopsisExpanded,
        synopsisExpandable,
        synopsisTranslated,
        translatedSynopsis,
        translatingSynopsis,
        onToggleTranslate,
        onToggleExpand,
    }: Props = $props();
</script>

<header class="flex flex-wrap items-start justify-between gap-4">
    <div class="min-w-0">
        {#if originalTitle}
            <p class="text-sm font-medium text-muted">{originalTitle}</p>
        {/if}
        <h1
            class="mt-1 break-words text-3xl font-extrabold tracking-tight text-white"
        >
            {title}
        </h1>
    </div>
</header>

<ul class="flex flex-wrap gap-2">
    {#each tags as tag, idx (`${tag}-${idx}`)}
        <li
            class="rounded-full bg-[color-mix(in_oklab,var(--color-accent)_20%,transparent)] px-3 py-1 text-xs font-medium text-[var(--color-accent-soft)]"
        >
            {tag}
        </li>
    {/each}
</ul>
<div class="flex flex-wrap items-center gap-2.5">
    {#each ratings as rating (rating.source)}
        {@const src = rating.source.toLowerCase()}
        <div
            class="inline-flex h-9 items-center gap-2 rounded-lg border px-3 shadow-sm transition hover:brightness-125 {sourceBadgeClasses(
                src,
            )}"
            title={`${rating.source}: ${rating.score !== null && rating.score > 0 ? rating.score.toFixed(1) : "—"}`}
        >
            <span
                class="flex items-center gap-1.5 text-[11px] font-black uppercase tracking-wider"
            >
                {#if src.includes("anilist")}
                    <svg
                        class="h-3.5 w-3.5 fill-current"
                        viewBox="0 0 24 24"
                        aria-hidden="true"
                        ><path
                            d="M24 17.561v4.425H13.678v-4.425zM12.924 2.014l7.157 15.547H14.88l-1.393-3.088H8.847l-1.385 3.088H2.179L9.345 2.014h3.579zm-.897 8.358L10.37 6.452l-1.65 3.92h3.307z"
                        /></svg
                    >
                    AniList
                {:else if src.includes("shikimori")}
                    Shikimori
                {:else if src.includes("mangadex")}
                    MangaDex
                {:else if src.includes("myanimelist") || src.includes("jikan") || src.includes("mal")}
                    MAL
                {:else if src.includes("tmdb")}
                    TMDB
                {:else if src.includes("rawg")}
                    RAWG
                {:else if src.includes("steam")}
                    Steam
                {:else if src.includes("igdb")}
                    IGDB
                {:else if src.includes("kitsu")}
                    Kitsu
                {:else if src.includes("simkl")}
                    Simkl
                {:else if src.includes("kinopoisk")}
                    Кинопоиск
                {:else if src.includes("imdb")}
                    IMDb
                {:else if src.includes("thetvdb") || src.includes("tvdb")}
                    TVDB
                {:else if src.includes("mangaupdate")}
                    MangaUpdates
                {:else if src.includes("openlibrary")}
                    OpenLibrary
                {:else}
                    <Star size={13} fill="currentColor" aria-hidden="true" />
                    {rating.source}
                {/if}
            </span>
            {#if rating.score !== null && rating.score > 0}
                <span class="text-sm font-extrabold tabular-nums text-white"
                    >{rating.score.toFixed(1)}</span
                >
                {#if rating.votes}
                    <span class="text-[11px] font-normal text-white/50"
                        >({rating.votes > 1000
                            ? (rating.votes / 1000).toFixed(1) + "k"
                            : rating.votes})</span
                    >
                {/if}
            {:else}
                <!-- No spinner here on purpose: the badges are rendered from the local
                     DB, so a source with no stored score means "no rating", not
                     "still being fetched". -->
                <span class="text-sm font-medium text-white/40">—</span>
            {/if}
        </div>
    {/each}
</div>
<section
    class="space-y-2 rounded-xl bg-[color-mix(in_oklab,var(--color-panel-line)_60%,transparent)] p-5 border border-white/[0.06]"
>
    <div class="flex items-center justify-between">
        <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
            {i18n.t.detail.synopsisTitle}
        </h2>
        {#if synopsisText}
            <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-medium text-[var(--color-accent-soft)] transition hover:bg-white/10 hover:text-white cursor-pointer disabled:opacity-50"
                disabled={translatingSynopsis}
                onclick={onToggleTranslate}
                title={synopsisTranslated
                    ? i18n.t.detail.showOriginal
                    : i18n.t.detail.translate}
            >
                {#if translatingSynopsis}
                    <div
                        class="h-3 w-3 animate-spin rounded-full border border-accent border-t-transparent"
                    ></div>
                    <span>{i18n.t.detail.translating}</span>
                {:else}
                    <Languages size={13} aria-hidden="true" />
                    <span
                        >{synopsisTranslated
                            ? i18n.t.detail.showOriginal
                            : i18n.t.detail.translate}</span
                    >
                {/if}
            </button>
        {/if}
    </div>
    {#if synopsisText}
        <p
            class={`whitespace-pre-line break-words text-sm leading-relaxed text-[var(--color-ink-dim)] ${synopsisExpandable && !synopsisExpanded ? "line-clamp-4" : ""}`}
        >
            {synopsisTranslated && translatedSynopsis
                ? translatedSynopsis
                : synopsisText}
        </p>
        {#if synopsisExpandable}
            <button
                type="button"
                class="inline-flex items-center gap-1 pt-1 text-xs font-semibold text-[var(--color-accent-soft)] transition hover:text-white"
                onclick={onToggleExpand}
            >
                {synopsisExpanded
                    ? i18n.t.detail.collapse
                    : i18n.t.detail.readMore}
                <ChevronDown
                    size={14}
                    class={`transition ${synopsisExpanded ? "rotate-180" : ""}`}
                    aria-hidden="true"
                />
            </button>
        {/if}
    {:else}
        <p class="text-sm text-muted">{i18n.t.detail.noSynopsis}</p>
    {/if}
</section>