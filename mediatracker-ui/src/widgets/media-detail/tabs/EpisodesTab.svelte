<script lang="ts">
    import type { TvSeason } from "$shared/types";
    import type { EpisodeRow, NextUp } from "$widgets/media-detail/detailTypes";
    import TvShowDetailSection from "../sections/TvShowDetailSection.svelte";

    interface Props {
        seasons: readonly TvSeason[];
        /** The season banner renders whenever a season exists; the episode list only on its tab. */
        showEpisodes: boolean;
        nextUp: NextUp | null;
        seriesEpisodes: { current: number; total: number };
        seriesProgressPercent: number;
        episodeBusy: unknown;
        progressError: unknown;
        sortOrder: "asc" | "desc";
        onToggleSort: () => void;
        onToggleSeasonCompleteOf: (seasonId: string) => Promise<void>;
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
        showEpisodes,
        nextUp,
        seriesEpisodes,
        seriesProgressPercent,
        episodeBusy,
        progressError,
        sortOrder,
        onToggleSort,
        onToggleSeasonCompleteOf,
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
    {showEpisodes}
    {nextUp}
    {seriesEpisodes}
    {seriesProgressPercent}
    {episodeBusy}
    {progressError}
    {sortOrder}
    {onToggleSort}
    {onToggleSeasonCompleteOf}
    {onToggleEpisodeOf}
    {onWatchNextUp}
    {onOpenEpisodesTab}
    {onOpenLists}
    {formatDate}
    {episodesBySeason}
/>
