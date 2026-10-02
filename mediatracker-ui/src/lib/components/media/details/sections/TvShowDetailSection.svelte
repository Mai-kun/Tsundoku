<script lang="ts">
    import ArrowUpDown from "lucide-svelte/icons/arrow-up-down";
    import Check from "lucide-svelte/icons/check";
    import CheckCircle2 from "lucide-svelte/icons/check-circle-2";
    import Eye from "lucide-svelte/icons/eye";
    import List from "lucide-svelte/icons/list";
    import RotateCcw from "lucide-svelte/icons/rotate-ccw";
    import { errorMessage } from "$lib/api";
    import { i18n } from "$lib/i18n/index.svelte";
    import type { TvSeason } from "$lib/types";

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
        seasonProgressPercent: number;
        episodeBusy: unknown;
        progressError: unknown;
        sortOrder: "asc" | "desc";
        onSelectSeason: (seasonId: string) => void;
        onToggleSort: () => void;
        onMarkSeasonComplete: () => Promise<void>;
        onResetSeason: () => Promise<void>;
        onToggleEpisode: (number: number) => Promise<void>;
        onOpenEpisodesTab: () => void;
        onOpenLists: () => void;
        formatDate: (value: string | null) => string;
    }

    let {
        seasons,
        currentSeason,
        showEpisodes,
        sortedEpisodes,
        nextEpisode,
        seasonProgressPercent,
        episodeBusy,
        progressError,
        sortOrder,
        onSelectSeason,
        onToggleSort,
        onMarkSeasonComplete,
        onResetSeason,
        onToggleEpisode,
        onOpenEpisodesTab,
        onOpenLists,
        formatDate,
    }: Props = $props();
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
                {#if nextEpisode}
                    <button
                        type="button"
                        class="inline-flex items-center gap-2 rounded-lg bg-[var(--color-accent)] px-4 py-2 text-xs font-semibold text-white shadow-md transition hover:bg-[var(--color-accent-deep)] active:scale-95 disabled:opacity-50"
                        disabled={Boolean(episodeBusy)}
                        onclick={() => void onToggleEpisode(nextEpisode.number)}
                    >
                        <Check size={14} stroke-width={2.5} />
                        {i18n.t.detail.bannerNextEpisode}: E{nextEpisode.number}
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
                    {i18n.t.detail.tabEpisodes} →
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
            {#if seasons.length > 1}
                <select
                    class="h-9 rounded-md border border-white/[0.08] bg-[var(--color-field)] px-3 text-xs font-semibold text-white outline-none focus:ring-1 focus:ring-[var(--color-accent)]"
                    value={currentSeason?.id ?? ""}
                    onchange={(event) =>
                        onSelectSeason(
                            (event.currentTarget as HTMLSelectElement).value,
                        )}
                >
                    {#each seasons as value (value.id)}
                        <option value={value.id}
                            >{value.title ||
                                `Season ${value.seasonNumber}`}</option
                        >
                    {/each}
                </select>
            {:else if currentSeason}
                <span class="text-xs font-semibold text-white"
                    >{currentSeason.title}</span
                >
            {/if}

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
    {:else if sortedEpisodes.length === 0}
        <p class="rounded-xl bg-[var(--color-panel-line)] p-5 text-sm text-muted">
            {i18n.t.common.noData}
        </p>
    {:else}
        <div class="space-y-2">
            {#each sortedEpisodes as episode (episode.id)}
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
                            onclick={() => void onToggleEpisode(episode.number)}
                        >
                            {#if episode.watched}
                                <Check
                                    size={16}
                                    stroke-width={2.8}
                                    aria-hidden="true"
                                />
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
            {/each}
        </div>
        {#if progressError}<p class="text-xs text-rose-300" role="alert">
                {errorMessage(progressError)}
            </p>{/if}
    {/if}
</section>
{/if}