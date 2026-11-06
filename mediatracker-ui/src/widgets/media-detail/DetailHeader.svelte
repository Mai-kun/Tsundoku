<script lang="ts">
  import { ChevronDown, Languages, Star, Users } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";

  export interface RatingBadge {
    source: string;
    score: number | null;
    votes?: number | null;
  }

  /** 1317 → "1.3k"; the badge hover face has room for neither digits nor words to spare. */
  function formatVotes(votes: number): string {
    if (votes >= 1000) return `${(votes / 1000).toFixed(1)}k`;
    return String(votes);
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
    <h1 class="mt-1 text-3xl font-extrabold tracking-tight break-words text-white">
      {title}
    </h1>
    {#if originalTitle}
      <p class="text-muted mt-1.5 text-sm font-medium">{originalTitle}</p>
    {/if}
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
  {#each ratings.filter((r) => !/offline|офлайн/i.test(r.source)) as rating (rating.source)}
    {@const src = rating.source.toLowerCase()}
    {@const hasVotes = (rating.votes ?? 0) > 0}
    <div
      class="group relative inline-flex h-9 items-center overflow-hidden rounded-lg border px-3 shadow-sm transition {sourceBadgeClasses(
        src,
      )}"
      aria-label={`${rating.source}: ${rating.score !== null && rating.score > 0 ? rating.score.toFixed(1) : "—"}${hasVotes ? ` (${rating.votes})` : ""}`}
    >
      <!-- Front face: source + score. Votes moved to the hover overlay below. -->
      <div
        class="flex items-center gap-2 transition duration-200 ease-out group-hover:-translate-y-1.5 group-hover:opacity-0"
      >
        <span class="flex items-center gap-1.5 text-[11px] font-black tracking-wider uppercase">
          {#if src.includes("anilist")}
            <svg class="h-3.5 w-3.5 fill-current" viewBox="0 0 24 24" aria-hidden="true"
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
          <span class="text-sm font-extrabold text-white tabular-nums"
            >{rating.score.toFixed(1)}</span
          >
        {:else}
          <!-- No spinner here on purpose: the badges are rendered from the local
                       DB, so a source with no stored score means "no rating", not
                       "still being fetched". -->
          <span class="text-sm font-medium text-white/40">—</span>
        {/if}
      </div>
      <!-- Hover face: the vote count slides in over the badge. Without votes nothing overlays
                   and the badge stays static. -->
      {#if hasVotes}
        <div
          class="absolute inset-0 flex translate-y-full items-center justify-center gap-1 bg-black/45 text-[11px] font-semibold text-white opacity-0 transition duration-200 ease-out group-hover:translate-y-0 group-hover:opacity-100"
        >
          <Users size={11} aria-hidden="true" />
          <span class="tabular-nums">{formatVotes(rating.votes ?? 0)}</span>
        </div>
      {/if}
    </div>
  {/each}
</div>
<section
  class="space-y-2 rounded-xl border border-white/[0.06] bg-[color-mix(in_oklab,var(--color-panel-line)_60%,transparent)] p-5"
>
  <div class="flex items-center justify-between">
    <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
      {i18n.t.detail.synopsisTitle}
    </h2>
    {#if synopsisText}
      <button
        type="button"
        class="inline-flex cursor-pointer items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-medium text-[var(--color-accent-soft)] transition hover:bg-white/10 hover:text-white disabled:opacity-50"
        disabled={translatingSynopsis}
        onclick={onToggleTranslate}
        title={synopsisTranslated ? i18n.t.detail.showOriginal : i18n.t.detail.translate}
      >
        {#if translatingSynopsis}
          <div
            class="border-accent h-3 w-3 animate-spin rounded-full border border-t-transparent"
          ></div>
          <span>{i18n.t.detail.translating}</span>
        {:else}
          <Languages size={13} aria-hidden="true" />
          <span>{synopsisTranslated ? i18n.t.detail.showOriginal : i18n.t.detail.translate}</span>
        {/if}
      </button>
    {/if}
  </div>
  {#if synopsisText}
    <p
      class={`text-sm leading-relaxed break-words whitespace-pre-line text-[var(--color-ink-dim)] ${synopsisExpandable && !synopsisExpanded ? "line-clamp-4" : ""}`}
    >
      {synopsisTranslated && translatedSynopsis ? translatedSynopsis : synopsisText}
    </p>
    {#if synopsisExpandable}
      <button
        type="button"
        class="inline-flex items-center gap-1 pt-1 text-xs font-semibold text-[var(--color-accent-soft)] transition hover:text-white"
        onclick={onToggleExpand}
      >
        {synopsisExpanded ? i18n.t.detail.collapse : i18n.t.detail.readMore}
        <ChevronDown
          size={14}
          class={`transition ${synopsisExpanded ? "rotate-180" : ""}`}
          aria-hidden="true"
        />
      </button>
    {/if}
  {:else}
    <p class="text-muted text-sm">{i18n.t.detail.noSynopsis}</p>
  {/if}
</section>
