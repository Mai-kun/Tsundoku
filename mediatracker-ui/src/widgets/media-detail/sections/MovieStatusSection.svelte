<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Check, Clapperboard, Clock, Eye, Pencil } from "$shared/ui/Icons";
  import type { MediaDetail } from "$shared/types";
  import type { MediaStatus } from "$shared/types/enums";

  interface Props {
    media: MediaDetail;
    statusLabel: string;
    onEdit: () => void;
    onChangeStatus?: (status: MediaStatus) => void;
  }

  let { media, statusLabel, onEdit, onChangeStatus }: Props = $props();

  const isRu = $derived(i18n.current === "ru");

  const duration = $derived(media.type === "movie" ? (media.durationMinutes ?? 0) : 0);
  const hours = $derived(Math.floor(duration / 60));
  const mins = $derived(duration % 60);
  const durationShort = $derived(duration > 0 ? `${duration} ${isRu ? "мин." : "min."}` : null);
  const durationLong = $derived(
    hours > 0 ? (isRu ? `~${hours} ч. ${mins} мин.` : `~${hours}h ${mins}m`) : null,
  );

  const watchedOn = $derived(media.watchedOn ?? null);

  const isPlanned = $derived(media.status === 0);
  const isCompleted = $derived(media.status === 2);
</script>

<section
  class="space-y-4 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
>
  <div class="flex items-center justify-between gap-3">
    <div class="flex items-center gap-2">
      <Clapperboard size={16} class="text-accent-soft shrink-0" />
      <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
        {isRu ? "Хронометраж и статус" : "Runtime & Status"}
      </h2>
    </div>
    <button
      type="button"
      class="text-muted flex cursor-pointer items-center gap-1 rounded-md px-2 py-1 text-xs transition hover:bg-white/[0.06] hover:text-white"
      onclick={onEdit}
      title={i18n.t.detailModal.edit}
    >
      <Pencil size={12} />
      <span>{i18n.t.detailModal.edit}</span>
    </button>
  </div>

  {#if durationShort}
    <div class="flex flex-wrap items-baseline gap-2.5">
      <span class="text-3xl font-extrabold text-white tabular-nums">{durationShort}</span>
      {#if durationLong}
        <span class="text-sm font-medium text-slate-400">({durationLong})</span>
      {/if}
    </div>
  {/if}

  <div class="space-y-2 pt-1">
    <div class="text-muted text-[11px] font-semibold tracking-wider uppercase">
      {isRu ? "Быстрая смена статуса" : "Quick Status Change"}
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        class={`flex cursor-pointer items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition ${
          isPlanned
            ? "bg-[#5844e0] text-white shadow-sm ring-1 ring-[#5844e0]"
            : "border border-white/10 bg-white/[0.03] text-slate-300 hover:bg-white/10 hover:text-white"
        }`}
        onclick={() => onChangeStatus?.(0 as MediaStatus)}
        disabled={!onChangeStatus}
      >
        {#if isPlanned}<Check size={13} stroke-width={2.5} />{/if}
        <span>{i18n.t.status.planned}</span>
      </button>

      <button
        type="button"
        class={`flex cursor-pointer items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition ${
          isCompleted
            ? "bg-emerald-600 text-white shadow-sm ring-1 ring-emerald-500"
            : "border border-white/10 bg-white/[0.03] text-slate-300 hover:bg-white/10 hover:text-white"
        }`}
        onclick={() => onChangeStatus?.(2 as MediaStatus)}
        disabled={!onChangeStatus}
      >
        {#if isCompleted}<Check size={13} stroke-width={2.5} />{/if}
        <span>{i18n.t.status.completed}</span>
      </button>

      {#if !isPlanned && !isCompleted}
        <span
          class="rounded-lg border border-amber-400/30 bg-amber-400/10 px-2.5 py-1 text-xs font-medium text-amber-300"
        >
          {statusLabel}
        </span>
      {/if}
    </div>
  </div>

  {#if watchedOn}
    <div
      class="flex items-center gap-2 rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2 text-xs text-slate-300"
    >
      <Eye size={14} class="text-accent-soft shrink-0" />
      <span class="text-muted">{isRu ? "Где смотрено:" : "Watched on:"}</span>
      <span class="font-semibold text-white">{watchedOn}</span>
    </div>
  {/if}
</section>
