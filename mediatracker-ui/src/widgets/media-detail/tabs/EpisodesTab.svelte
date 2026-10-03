<script lang="ts">
    import type { TvSeason } from "$shared/types";
    import type { EpisodeRow, NextUp } from "$widgets/media-detail/detailTypes";
    import TvShowDetailSection from "../sections/TvShowDetailSection.svelte";

    interface Props {
        seasons: readonly TvSeason[];
        currentSeason: TvSeason | null;
        /** The season banner renders whenever a season exists; the episode list only on its tab. */
        showEpisodes: boolean;
        sortedEpisodes: readonly EpisodeRow[];
        nextEpisode: EpisodeRow | null;
        nextUp: NextUp | null;
        seasonProgressPercent: number;
        episodeBusy: unknown;
        progressError: unknown;
        sortOrder: "asc" | "desc";
        onSelectSeason: (seasonId: string) => void;
        onToggleSort: () => void;
        onMarkSeasonComplete: () => Promise<void>;
        onMarkSeasonCompleteOf: (seasonId: string) => Promise<void>;
        onResetSeason: () => Promise<void>;
        onToggleEpisode: (number: number) => Promise<void>;
        onToggleEpisodeOf: (seasonId: string, number: number) => Promise<void>;
        onWatchNextUp: (target: NextUp) => Promise<void>;
        onOpenEpisodesTab: () => void;
        onOpenLists: () => void;
        formatDate: (value: string | null) => string;
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
</script>

<TvShowDetailSection
    {seasons}
    {currentSeason}
    {showEpisodes}
    {sortedEpisodes}
    {nextEpisode}
    {nextUp}
    {seasonProgressPercent}
    {episodeBusy}
    {progressError}
    {sortOrder}
    {onSelectSeason}
    {onToggleSort}
    {onMarkSeasonComplete}
    {onMarkSeasonCompleteOf}
    {onResetSeason}
    {onToggleEpisode}
    {onToggleEpisodeOf}
    {onWatchNextUp}
    {onOpenEpisodesTab}
    {onOpenLists}
    {formatDate}
    {episodesBySeason}
/>
