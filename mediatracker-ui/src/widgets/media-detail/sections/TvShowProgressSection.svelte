<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { formatNumber } from "$entities/media/model/mediaLabels";
  import ProgressCard from "./ProgressCard.svelte";
  import type { ProgressInfo } from "../detailTypes";
  import type { MediaDetail, TvShowMedia, TvSeason } from "$shared/types";

  interface Props {
    media: MediaDetail;
    totalEpisodes: number;
    watchedEpisodes: number;
    progress: ProgressInfo;
    value: number;
    percent: number;
    error: unknown;
    onStep: (delta: number) => void;
    onCounterChange?: (value: number) => void;
  }

  let {
    media,
    totalEpisodes,
    watchedEpisodes,
    progress,
    value,
    percent,
    error,
    onStep,
    onCounterChange,
  }: Props = $props();

  const tvMedia = $derived(media as unknown as TvShowMedia);
  const duration = $derived(tvMedia.episodeDurationMinutes || tvMedia.durationMinutes || 24);

  /** All seasons of the show, when the detail payload carried them. */
  const seasons = $derived((media as { seasons?: TvSeason[] }).seasons ?? []);
  /** "Season 1: 220 · Season 2: 280" — a tooltip on the total, shown only for multi-season shows. */
  const totalTooltip = $derived(
    seasons.length > 1
      ? seasons
          .map(
            (s) => `${i18n.t.progress.seasonN(s.seasonNumber)}: ${formatNumber(s.totalEpisodes)}`,
          )
          .join(" · ")
      : null,
  );

  const effectiveTotal = $derived(totalEpisodes > 0 ? totalEpisodes : (progress.total ?? 0));
</script>

<ProgressCard
  label={i18n.t.progress.unitsEpisodes}
  unitShort={i18n.t.progress.unitShortEp}
  unitNoun={i18n.t.progress.unitNounSeries}
  accent="indigo"
  {value}
  total={effectiveTotal}
  {percent}
  minsPerUnit={duration}
  doneLabel={i18n.t.progress.watchedVerb}
  remainLabel={i18n.t.progress.remainWatchVerb}
  paceOptions={[1, 2, 3, 5]}
  paceDefault={2}
  startHint={i18n.t.progress.startSeries}
  {totalTooltip}
  finishedAt={media.finishedAt}
  {error}
  {onStep}
  {onCounterChange}
/>
