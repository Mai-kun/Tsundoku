<script lang="ts">
    import type { TvSeason } from "$shared/types";
    import type { EpisodeRow } from "../detailTypes";
    import TvShowDetailSection from "../sections/TvShowDetailSection.svelte";

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

<TvShowDetailSection
    {seasons}
    {currentSeason}
    {showEpisodes}
    {sortedEpisodes}
    {nextEpisode}
    {seasonProgressPercent}
    {episodeBusy}
    {progressError}
    {sortOrder}
    {onSelectSeason}
    {onToggleSort}
    {onMarkSeasonComplete}
    {onResetSeason}
    {onToggleEpisode}
    {onOpenEpisodesTab}
    {onOpenLists}
    {formatDate}
/>
