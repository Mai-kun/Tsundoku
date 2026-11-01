<script lang="ts">
  import { Trash2 } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { GoalDto } from "$shared/types";

  interface Props {
    goal: GoalDto;
    onOpenMedia: (id: string) => void;
    onDelete: (goal: GoalDto) => void;
  }

  let { goal, onOpenMedia, onDelete }: Props = $props();

  const percent = $derived(
    goal.targetCount > 0
      ? Math.min(100, Math.round((goal.currentCount / goal.targetCount) * 100))
      : 0,
  );
</script>

<article
  class="bg-card group relative flex flex-col gap-3 rounded-xl border border-white/[0.08] p-4 transition hover:border-white/20"
>
  <button
    type="button"
    class="text-muted hover:bg-elevated hover:text-ink absolute top-3 right-3 z-10 hidden h-8 w-8 cursor-pointer place-items-center rounded-md border border-white/10 transition group-hover:grid"
    aria-label={i18n.t.goals.deleteGoal}
    title={i18n.t.goals.deleteGoal}
    onclick={() => onDelete(goal)}
  >
    <Trash2 size={14} />
  </button>

  <div class="flex items-start gap-3">
    <span
      class="bg-elevated grid size-11 shrink-0 place-items-center rounded-lg border border-white/[0.08] text-xl"
      aria-hidden="true"
    >
      {goal.icon}
    </span>
    <div class="min-w-0 flex-1 pr-8">
      <h3 class="text-ink truncate text-sm font-semibold">{goal.title}</h3>
      {#if goal.description}
        <p class="text-muted mt-0.5 line-clamp-2 text-xs leading-relaxed">{goal.description}</p>
      {/if}
    </div>
  </div>

  <div>
    <div class="mb-1.5 flex items-baseline justify-between gap-2">
      <span class="text-ink text-sm font-bold tabular-nums">
        {goal.currentCount} / {goal.targetCount}
      </span>
      <span class="text-muted text-xs font-medium tabular-nums">{percent}%</span>
    </div>
    <div
      class="bg-track h-2.5 w-full overflow-hidden rounded-full"
      role="progressbar"
      aria-valuenow={goal.currentCount}
      aria-valuemin={0}
      aria-valuemax={goal.targetCount}
      aria-label={goal.title}
    >
      <div
        class={`h-full rounded-full transition-[width] duration-500 ease-out ${
          goal.isCompleted ? "bg-emerald-500/80" : "bg-gradient-to-r from-[#5844e0] to-[#818cf8]"
        }`}
        style={`width: ${percent}%`}
      ></div>
    </div>
    {#if goal.isCompleted}
      <span
        class="mt-2 inline-flex items-center rounded-md border border-emerald-400/40 bg-emerald-500/15 px-2 py-0.5 text-[11px] font-semibold text-emerald-300"
      >
        {i18n.t.goals.completedBadge}
      </span>
    {/if}
  </div>

  {#if goal.completedItems.length > 0}
    <div class="flex items-center gap-1.5" title={i18n.t.goals.overallProgress}>
      {#each goal.completedItems as item (item.id)}
        <button
          type="button"
          class="hover:border-ink/40 size-12 shrink-0 cursor-pointer overflow-hidden rounded-md border border-white/10 transition hover:scale-105"
          title={item.title}
          onclick={() => onOpenMedia(item.id)}
        >
          {#if item.coverUrl}
            <img
              src={item.coverUrl}
              alt={item.title}
              class="h-full w-full object-cover"
              loading="lazy"
            />
          {:else}
            <span class="text-muted grid h-full w-full place-items-center text-[10px]">?</span>
          {/if}
        </button>
      {/each}
    </div>
  {:else}
    <p class="text-muted text-xs">{i18n.t.goals.noMatches}</p>
  {/if}
</article>
