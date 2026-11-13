<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import ProgressCard from "./ProgressCard.svelte";
  import type { ProgressInfo } from "../detailTypes";
  import type { MangaDetail } from "$shared/types";

  interface Props {
    media: MangaDetail;
    totalChapters: number;
    currentChapter: number;
    progress: ProgressInfo;
    value: number;
    percent: number;
    error: unknown;
    onStep: (delta: number) => void;
    onCounterChange?: (value: number) => void;
  }

  let {
    media,
    totalChapters,
    currentChapter,
    progress,
    value,
    percent,
    error,
    onStep,
    onCounterChange,
  }: Props = $props();

  const minsPerChapter = $derived(uiSettings.mangaChapterMinutes || 6.0);
  const effectiveTotal = $derived(totalChapters > 0 ? totalChapters : (progress.total ?? 0));
</script>

<ProgressCard
  label={i18n.t.progress.unitsChapters}
  unitShort={i18n.t.progress.unitShortCh}
  unitNoun={i18n.t.progress.unitNounChapter}
  accent="amber"
  {value}
  total={effectiveTotal}
  {percent}
  minsPerUnit={minsPerChapter}
  doneLabel={i18n.t.progress.readVerb}
  remainLabel={i18n.t.progress.remainReadVerb}
  paceOptions={[1, 2, 3, 5]}
  paceDefault={5}
  startHint={i18n.t.progress.startChapters}
  finishedAt={media.finishedAt}
  {error}
  {onStep}
  {onCounterChange}
/>
