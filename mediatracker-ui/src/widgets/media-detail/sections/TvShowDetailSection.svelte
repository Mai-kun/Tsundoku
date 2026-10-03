﻿<script lang="ts">
    import { ArrowUpDown, Check, CheckCircle2, ChevronDown, Eye, List, Play, RotateCcw } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { TvSeason } from "$shared/types";
    import type { NextUp } from "$widgets/media-detail/detailTypes";

    export interface EpisodeRow {
        id: string;
        number: number;
        title: string;
        description: string | null;
        airDate: string | null;
        watched: boolean;
    }

    interface Props {
        seasons: readonly TvSeason[];
        currentSeason: TvSeason | null;
        /** The season banner renders whenever a season exists; the episode list only on its tab. */
        showEpisodes: boolean;
        sortedEpisodes: readonly EpisodeRow[];
        nextEpisode: EpisodeRow | null;
        /** The first unwatched episode of the whole series, crossing season boundaries. */
        nextUp: NextUp | null;
        seasonProgressPercent: number;
        episodeBusy: unknown;
        progressError: unknown;
        sortOrder: "asc" | "desc";
        onSelectSeason: (seasonId: string) => void;
        onToggleSort: () => void;
        onMarkSeasonComplete: () => Promise<void>;
        /** Same, but for a season chosen inside an accordion rather than the selected one. */
        onMarkSeasonCompleteOf: (seasonId: string) => Promise<void>;
        onResetSeason: () => Promise<void>;
        onToggleEpisode: (number: number) => Promise<void>;
        /** Same toggle, but for a season chosen inside an accordion rather than the selected one. */
        onToggleEpisodeOf: (seasonId: string, number: number) => Promise<void>;
        /** Jumps to the next unwatched episode, selecting and expanding its season first. */
        onWatchNextUp: (target: NextUp) => Promise<void>;
        onOpenEpisodesTab: () => void;
        onOpenLists: () => void;
        formatDate: (value: string | null) => string;
        /** Every season's episodes, keyed by season id, so each accordion renders its own list. */
        episodesBySeason?: readonly {
            season: TvSeason;
            episodes: readonly EpisodeRow[];
        }[];
    }

    let {
        seasons,
        currentSeason,
        showEpisodes,
        sortedEpisodes,
        nextEpisode,
        nextUp,
        seasonProgressPercent,
        episodeBusy,
        progressError,
        sortOrder,
        onSelectSeason,
        onToggleSort,
        onMarkSeasonComplete,
        onMarkSeasonCompleteOf,
        onResetSeason,
        onToggleEpisode,
        onToggleEpisodeOf,
        onWatchNextUp,
        onOpenEpisodesTab,
        onOpenLists,
        formatDate,
        episodesBySeason = [],
    }: Props = $props();

    /** Every season's episodes, so each accordion renders its own list rather than only the selected one. */
    const orderedBySort = (rows: readonly EpisodeRow[]) =>
        sortOrder === "asc" ? rows : [...rows].reverse();
</script>
{#if currentSeason}
    <div
        class="relative overflow-hidden rounded-xl border border-white/[0.08] bg-gradient-to-r from-[var(--color-overlay-strong)] via-[var(--color-panel-line)] to-[var(--color-overlay-strong)] p-5 shadow-lg"
    >
        <div class="flex flex-wrap items-center justify-between gap-4">
            <div class="min-w-0">
                <p
                    class="text-xs font-semibold uppercase tracking-wider text-[var(--color-accent-soft)]"
                >
                    {currentSeason.title}
                </p>
                <p class="mt-1 text-lg font-bold text-white">
                    {i18n.t.card.episodes(
                        currentSeason.currentEpisode,
                        currentSeason.totalEpisodes,
                    )}
                    <span class="ml-2 text-xs font-medium text-muted"
                        >({Math.round(seasonProgressPercent)}%)</span
                    >
                </p>
            </div>

            <div class="flex items-center gap-2">
                <!-- The series-wide next episode: once a season is finished this rolls over to
                     "S2 E1" on its own instead of leaving the user on a dead season. -->
                {#if nextUp}
                    <button
                        type="button"
                        class="inline-flex items-center gap-2 rounded-lg bg-[var(--color-accent)] px-4 py-2 text-xs font-semibold text-white shadow-md transition hover:bg-[var(--color-accent-deep)] active:scale-95 disabled:opacity-50"
                        disabled={Boolean(episodeBusy)}
                        title={i18n.t.detail.bannerNextEpisode}
                        onclick={() => void onWatchNextUp(nextUp)}
                    >
                        <Play size={14} stroke-width={2.5} />
                        {i18n.t.detail.bannerNextEpisode}: S{nextUp.seasonNumber} E{nextUp.episodeNumber}
                    </button>
                {:else if currentSeason.totalEpisodes && currentSeason.currentEpisode >= currentSeason.totalEpisodes}
                    <span
                        class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-500/15 px-3 py-1.5 text-xs font-semibold text-emerald-300"
                    >
                        <CheckCircle2 size={15} />
                        {i18n.t.detail.bannerCompleted}
                    </span>
                {/if}

                <button
                    type="button"
                    class="rounded-lg border border-white/[0.08] bg-surface/50 px-3 py-2 text-xs font-medium text-muted transition hover:bg-white/10 hover:text-white"
                    onclick={onOpenEpisodesTab}
                >
                    {i18n.t.detail.tabEpisodes} в†’
                </button>
            </div>
        </div>

        <div class="mt-4 h-2 w-full max-w-2xl overflow-hidden rounded-full bg-black/40">
            <div
                class="h-full rounded-full bg-gradient-to-r from-[var(--color-accent)] to-[var(--color-info-soft)] transition-all duration-300"
                style={`width: ${seasonProgressPercent}%`}
            ></div>
        </div>
    </div>
{/if}
{#if showEpisodes}
    <section class="space-y-4">
    <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-[var(--color-panel-line)] p-3.5"
    >
        <div class="flex items-center gap-3">
            {#if currentSeason}
                <span class="text-xs text-muted">
                    {i18n.t.card.episodes(
                        currentSeason.currentEpisode,
                        currentSeason.totalEpisodes,
                    )}
                </span>
            {/if}
        </div>

        <div class="flex items-center gap-2">
            <button
                type="button"
                class="inline-flex h-8 items-center gap-1.5 rounded-md border border-white/[0.08] bg-surface/50 px-2.5 text-xs font-medium text-white transition hover:bg-white/10"
                onclick={onToggleSort}
                title="Toggle episode sort order"
            >
                <ArrowUpDown
                    size={13}
                    class="text-[var(--color-accent-soft)]"
                    aria-hidden="true"
                />
                {sortOrder === "asc"
                    ? i18n.t.detail.sortAsc
                    : i18n.t.detail.sortDesc}
            </button>

            <button
                type="button"
                class="inline-flex h-8 items-center gap-1.5 rounded-md bg-emerald-500/20 border border-emerald-500/30 px-2.5 text-xs font-semibold text-emerald-300 transition hover:bg-emerald-500/30 disabled:opacity-50"
                disabled={Boolean(episodeBusy)}
                onclick={() => void onMarkSeasonComplete()}
            >
                <Check size={13} stroke-width={2.5} />
                {i18n.t.detail.markSeasonWatched}
            </button>

            <button
                type="button"
                class="inline-flex h-8 items-center gap-1.5 rounded-md bg-rose-500/10 border border-rose-500/20 px-2.5 text-xs font-semibold text-rose-300 transition hover:bg-rose-500/20 disabled:opacity-50"
                disabled={Boolean(episodeBusy)}
                onclick={() => void onResetSeason()}
            >
                <RotateCcw size={13} />
                {i18n.t.detail.resetSeason}
            </button>
        </div>
    </div>
{#if seasons.length === 0}
        <p class="rounded-xl bg-[var(--color-panel-line)] p-5 text-sm text-muted">
            {i18n.t.views.noSeasons}
        </p>
    {:else}
        <!-- One collapsible block per season. A <details> gives the open/close behaviour, the
             keyboard support and the aria wiring for free; expanding also selects the season so the
             action bar above and every episode toggle act on what the user is looking at. -->
        <div class="space-y-2">
            {#each seasons as season (season.id)}
                {@const rows = orderedBySort(
                    episodesBySeason.find((view) => view.season.id === season.id)
                        ?.episodes ??
                        (season.id === currentSeason?.id ? sortedEpisodes : []),
                )}
                <details
                    class="group overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)]"
                    open={season.id === currentSeason?.id}
                    ontoggle={(event) => {
                        // The action bar above acts on the *selected* season, so expanding a season has
                        // to select it; otherwise a user could open season 3 and mark season 1 done.
                        const details = event.currentTarget;
                        if (details.open && season.id !== currentSeason?.id) {
                            onSelectSeason(season.id);
                        }
                    }}
                >
                    <summary
                        class="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 transition hover:bg-white/[0.04]"
                    >
                        <span class="flex min-w-0 items-center gap-2">
                            <ChevronDown
                                size={16}
                                class="shrink-0 text-[var(--color-accent-soft)] transition-transform duration-200 group-open:rotate-180"
                                aria-hidden="true"
                            />
                            <span class="truncate text-sm font-semibold text-white">
                                {season.title || `Season ${season.seasonNumber}`}
                            </span>
                        </span>
                        <span class="flex shrink-0 items-center gap-2">
                            <span class="text-xs text-muted">
                                {i18n.t.card.episodes(
                                    season.currentEpisode,
                                    season.totalEpisodes,
                                )}
                            </span>
                            <!-- Marks this whole season watched straight from its header. The eye is
                                 hidden once the season is done, because there is nothing left to do. -->
                            {#if season.totalEpisodes > 0 && season.currentEpisode < season.totalEpisodes}
                                <button
                                    type="button"
                                    class="grid h-7 w-7 place-items-center rounded-full border border-white/[0.08] bg-[var(--color-field)] text-[var(--color-muted)] transition hover:border-emerald-500/40 hover:bg-emerald-500/20 hover:text-emerald-400 disabled:cursor-wait disabled:opacity-60"
                                    aria-label={i18n.t.detail.markSeasonWatched}
                                    title={i18n.t.detail.markSeasonWatched}
                                    disabled={Boolean(episodeBusy)}
                                    onclick={(event) => {
                                        // The header is a <summary>, so a plain click would also toggle
                                        // the accordion open and re-select the season.
                                        event.preventDefault();
                                        event.stopPropagation();
                                        void onMarkSeasonCompleteOf(season.id);
                                    }}
                                >
                                    <Eye size={14} aria-hidden="true" />
                                </button>
                            {:else if season.totalEpisodes > 0}
                                <Check
                                    size={16}
                                    stroke-width={2.8}
                                    class="text-emerald-400"
                                    aria-label={i18n.t.detail.markSeasonWatched}
                                />
                            {/if}
                        </span>
                    </summary>

                    <div class="border-t border-white/[0.06] p-3">
                        {#if rows.length === 0}
                            <p class="px-1 py-3 text-sm text-muted">
                                {i18n.t.common.noData}
                            </p>
                        {:else}
                            <!-- Capped and scrollable: Breaking Bad has 62 episodes and an
                                 uncapped list pushed the rest of the detail page off screen. -->
                            <div
                                class="thin-scroll max-h-[520px] space-y-2 overflow-y-auto pr-1"
                            >
                                {#each rows as episode (episode.id)}
                                    {@render episodeRow(episode, season.id)}
                                {/each}
                            </div>
                        {/if}
                    </div>
                </details>
            {/each}
        </div>
                    {#if progressError}<p class="text-xs text-rose-300" role="alert">
                {errorMessage(progressError)}
            </p>{/if}
    {/if}
</section>
{/if}

{#snippet episodeRow(episode: EpisodeRow, seasonId: string)}
    <article
        class="flex items-center gap-3.5 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-3.5 transition hover:bg-[var(--color-panel-raised)]"
    >
        <span
            class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[var(--color-field)] text-xs font-bold text-[var(--color-muted)]"
        >
            E{episode.number}
        </span>
        <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-white">
                {episode.title}
            </p>
            {#if episode.airDate}
                <p class="mt-0.5 text-xs text-muted">
                    {formatDate(episode.airDate)}
                </p>
            {/if}
            {#if episode.description}
                <p
                    class="mt-1 line-clamp-2 text-xs leading-relaxed text-[var(--color-muted)]"
                >
                    {episode.description}
                </p>
            {/if}
        </div>

        <div class="flex shrink-0 items-center gap-2">
            <button
                type="button"
                class={`grid h-8 w-8 place-items-center rounded-full border transition active:scale-95 disabled:cursor-wait disabled:opacity-60 ${
                    episode.watched
                        ? "border-emerald-500/40 bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30"
                        : "border-white/[0.08] bg-[var(--color-field)] text-[var(--color-muted)] hover:bg-[var(--color-panel-line)] hover:text-white"
                }`}
                aria-label={episode.watched
                    ? i18n.t.detail.markWatched
                    : i18n.t.detail.watchAction}
                title={episode.watched
                    ? i18n.t.detail.unwatchAction
                    : i18n.t.detail.markWatched}
                disabled={Boolean(episodeBusy)}
                onclick={() => onToggleEpisodeOf(seasonId, episode.number)}
            >
                {#if episode.watched}
                    <Check size={16} stroke-width={2.8} aria-hidden="true" />
                {:else}
                    <Eye size={15} aria-hidden="true" />
                {/if}
            </button>

            <button
                type="button"
                class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-[var(--color-field)] hover:text-white"
                aria-label={i18n.t.views.listsTitle}
                title={i18n.t.views.listsTitle}
                onclick={onOpenLists}
            >
                <List size={15} aria-hidden="true" />
            </button>
        </div>
    </article>
{/snippet}
