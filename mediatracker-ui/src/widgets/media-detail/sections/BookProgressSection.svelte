<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import ProgressCard from "./ProgressCard.svelte";
  import type { ProgressInfo } from "../detailTypes";

  interface Props {
    totalPages: number;
    currentPage: number;
    format?: string | null;
    totalChapters?: number | null;
    currentChapter?: number | null;
    finishedAt?: string | null;
    progress: ProgressInfo;
    value: number;
    percent: number;
    error: unknown;
    onStep: (delta: number) => void;
    onCounterChange?: (value: number) => void;
  }

  let {
    totalPages,
    currentPage,
    format,
    totalChapters,
    currentChapter,
    finishedAt = null,
    progress,
    value,
    percent,
    error,
    onStep,
    onCounterChange,
  }: Props = $props();

  const isNovel = $derived(format === "light_novel" || format === "web_novel");
  const minsPerUnit = $derived(isNovel ? 6 : uiSettings.bookPageMinutes || 1.5);

  const effectiveTotal = $derived(
    isNovel
      ? totalChapters && totalChapters > 0
        ? totalChapters
        : (progress.total ?? 0)
      : totalPages > 0
        ? totalPages
        : (progress.total ?? 0),
  );
</script>

<ProgressCard
  label={isNovel ? i18n.t.progress.unitsChapters : i18n.t.progress.unitsPages}
  unitShort={isNovel ? i18n.t.progress.unitShortCh : i18n.t.progress.unitShortPg}
  unitNoun={isNovel ? i18n.t.progress.unitNounChapter : i18n.t.progress.unitNounPage}
  accent="amber"
  {value}
  total={effectiveTotal}
  {percent}
  {minsPerUnit}
  doneLabel={i18n.t.progress.readVerb}
  remainLabel={i18n.t.progress.remainReadVerb}
  paceOptions={isNovel ? [1, 2, 3, 5] : [10, 20, 30, 50]}
  paceDefault={isNovel ? 3 : 20}
  startHint={isNovel ? i18n.t.progress.startChapters : i18n.t.progress.startPages}
  {finishedAt}
  {error}
  {onStep}
  {onCounterChange}
/>
