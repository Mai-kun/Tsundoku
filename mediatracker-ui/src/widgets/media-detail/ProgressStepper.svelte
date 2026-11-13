<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import ProgressCard from "./sections/ProgressCard.svelte";
  import type { ProgressInfo } from "./detailTypes";

  interface Props {
    progress: ProgressInfo;
    value: number;
    percent: number;
    error: unknown;
    onStep: (delta: number) => void;
    onCounterChange?: (value: number) => void;
  }

  let { progress, value, percent, error, onStep, onCounterChange }: Props = $props();

  const total = $derived(progress.total ?? 0);
</script>

<ProgressCard
  label={progress.label}
  unitShort=""
  accent="theme"
  {value}
  {total}
  {percent}
  minsPerUnit={null}
  doneLabel={progress.label}
  remainLabel={progress.label}
  paceOptions={[]}
  startHint={i18n.t.progress.startGeneric}
  {error}
  {onStep}
  {onCounterChange}
/>
