<script lang="ts">
  import { untrack } from "svelte";
  import { Trophy } from "$shared/ui/Icons";
  import { deleteGoal, getGoals } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { markStart, markEnd } from "$shared/utils/perfMarks";
  import GoalCard from "$widgets/goals/GoalCard.svelte";
  import CreateGoalModal from "$features/goals/CreateGoalModal.svelte";
  import type { GoalDto } from "$shared/types";

  interface Props {
    refreshKey: number;
    onOpenMedia: (id: string) => void;
    onMediaChanged: () => void;
  }

  let { refreshKey, onOpenMedia, onMediaChanged }: Props = $props();

  const currentYear = new Date().getFullYear();
  const years = [currentYear - 1, currentYear, currentYear + 1];

  let year = $state(currentYear);
  let goals = $state<GoalDto[]>([]);
  let loading = $state(true);
  let loadError: unknown = $state(null);
  let isCreateOpen = $state(false);

  let requestSequence = 0;

  $effect(() => {
    void refreshKey;
    void year;
    const sequence = ++requestSequence;
    void loadGoals(sequence);
  });

  async function loadGoals(sequence: number) {
    markStart("tsundoku:goals:load");
    loading = goals.length === 0;
    loadError = null;
    try {
      const loaded = await getGoals(year);
      if (sequence === requestSequence) {
        goals = loaded;
        loading = false;
      }
    } catch (error) {
      if (sequence === requestSequence) {
        loadError = error;
        loading = false;
      }
    } finally {
      markEnd("tsundoku:goals:load");
    }
  }

  const completedCount = $derived(goals.filter((goal) => goal.isCompleted).length);
  const overallPercent = $derived(
    goals.length === 0 ? 0 : Math.round((completedCount / goals.length) * 100),
  );
  // Ring geometry: r=34, so 2πr ≈ 213.6 — the dash offset animates the arc.
  const RING_LENGTH = 2 * Math.PI * 34;

  async function removeGoal(goal: GoalDto) {
    if (!window.confirm(i18n.t.goals.deleteConfirm(goal.title))) return;
    try {
      await deleteGoal(goal.id);
      goals = goals.filter((g) => g.id !== goal.id);
      showToast(i18n.t.goals.deleted, "success");
    } catch {
      showToast(i18n.t.errors.unexpected, "error");
    }
  }

  function onGoalCreated(_goal: GoalDto) {
    void loadGoals(++requestSequence);
    untrack(() => onMediaChanged());
  }
</script>

<div class="space-y-6">
  <p class="text-muted flex items-center gap-2 text-xs font-medium">
    {#if loading && goals.length === 0}
      {i18n.t.common.loading}
    {/if}
  </p>

  <div class="flex flex-wrap items-center justify-between gap-4">
    <div class="flex items-center gap-4">
      <!-- Summary ring: share of goals closed this year -->
      <div
        class="relative grid size-20 shrink-0 place-items-center"
        role="img"
        aria-label={i18n.t.goals.summaryOf(completedCount, goals.length)}
      >
        <svg class="size-20 -rotate-90" viewBox="0 0 80 80" aria-hidden="true">
          <circle cx="40" cy="40" r="34" class="fill-none stroke-[#2a3040]" stroke-width="7" />
          <circle
            cx="40"
            cy="40"
            r="34"
            class="fill-none stroke-[#818cf8] transition-[stroke-dashoffset] duration-500 ease-out"
            stroke-width="7"
            stroke-linecap="round"
            stroke-dasharray={RING_LENGTH}
            stroke-dashoffset={RING_LENGTH * (1 - overallPercent / 100)}
          />
        </svg>
        <span class="text-ink absolute text-sm font-bold tabular-nums">{overallPercent}%</span>
      </div>
      <div>
        <p class="text-ink text-sm font-semibold">
          {i18n.t.goals.summaryOf(completedCount, goals.length)}
        </p>
        <p class="text-muted mt-0.5 text-xs">{i18n.t.goals.overallProgress}</p>
      </div>
    </div>

    <div class="flex items-center gap-2.5">
      <div class="bg-elevated flex overflow-hidden rounded-lg border border-white/[0.08]">
        {#each years as option (option)}
          <button
            type="button"
            class={`cursor-pointer px-3.5 py-2 text-sm font-medium transition ${
              year === option
                ? "bg-[#5844e0]/20 font-semibold text-[#a5b4fc]"
                : "text-muted hover:text-ink"
            }`}
            aria-pressed={year === option}
            onclick={() => (year = option)}
          >
            {option}
          </button>
        {/each}
      </div>
      <button
        type="button"
        class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-[#818cf8]/40 bg-[#5446cf]/80 px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#5446cf]"
        onclick={() => (isCreateOpen = true)}
      >
        <Trophy size={16} aria-hidden="true" />
        {i18n.t.goals.createGoal}
      </button>
    </div>
  </div>

  {#if loadError}
    <div
      class="flex items-center gap-2.5 rounded-lg border border-rose-400/25 bg-rose-400/10 p-3.5 text-xs text-rose-200"
      role="alert"
    >
      <span class="shrink-0 font-bold">!</span>
      <span>{i18n.t.goals.loadFailed}</span>
    </div>
  {:else if goals.length === 0 && !loading}
    <div
      class="bg-card/50 text-muted rounded-xl border border-dashed border-white/10 p-10 text-center text-sm"
    >
      {i18n.t.goals.empty}
    </div>
  {:else}
    <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
      {#each goals as goal (goal.id)}
        <GoalCard {goal} {onOpenMedia} onDelete={(g) => void removeGoal(g)} />
      {/each}
    </div>
    {#if goals.length > 0 && completedCount === 0}
      <p class="text-muted text-center text-xs">{i18n.t.goals.finishHint}</p>
    {/if}
  {/if}
</div>

{#if isCreateOpen}
  <CreateGoalModal
    isOpen={isCreateOpen}
    {year}
    onClose={() => (isCreateOpen = false)}
    onCreated={onGoalCreated}
  />
{/if}
