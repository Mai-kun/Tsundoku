<script lang="ts">
  import { Image, Sparkles } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { CriticalDivergence, DivergenceItem } from "$shared/types";

  interface Props {
    divergence: CriticalDivergence;
    onOpenMedia?: (mediaId: string) => void;
  }

  let { divergence, onOpenMedia }: Props = $props();

  function deltaStyle(delta: number): string {
    return delta >= 0
      ? "text-emerald-300 bg-emerald-500/10 border-emerald-500/20"
      : "text-rose-300 bg-rose-500/10 border-rose-500/20";
  }

  function deltaText(delta: number): string {
    return `${delta >= 0 ? "+" : ""}${delta}`;
  }

  function typeLabel(type: string): string {
    const labels = i18n.t.stats.genreCategories as Record<string, string>;
    return type in labels ? labels[type] : type;
  }
</script>

<div class="rounded-xl border border-white/5 bg-[#151a26] p-5">
  <div class="mb-4 flex items-center gap-2">
    <Sparkles class="size-4 text-amber-400" aria-hidden="true" />
    <h3 class="text-base font-semibold tracking-tight text-white">
      {i18n.t.stats.taste.divergenceTitle}
    </h3>
  </div>

  {#if !divergence.hiddenGem && !divergence.disappointment}
    <p class="text-muted flex min-h-32 items-center justify-center text-xs">
      {i18n.t.stats.taste.divergenceEmpty}
    </p>
  {:else}
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {#each [{ item: divergence.hiddenGem, kind: "gem" }, { item: divergence.disappointment, kind: "disappointment" }] as card (card.kind)}
        {@const item = card.item}
        {@const isGem = card.kind === "gem"}
        {#if item}
          {@const header = isGem ? i18n.t.stats.taste.hiddenGem : i18n.t.stats.taste.disappointment}
          {@const hint = isGem
            ? i18n.t.stats.taste.hiddenGemHint
            : i18n.t.stats.taste.disappointmentHint}
          {@const userFirst = isGem}
          <button
            type="button"
            class="group flex flex-col gap-3 rounded-lg border p-4 text-left transition {isGem
              ? 'border-emerald-500/20 bg-emerald-500/5 hover:border-emerald-400/40'
              : 'border-rose-500/20 bg-rose-500/5 hover:border-rose-400/40'} {onOpenMedia
              ? 'cursor-pointer'
              : 'cursor-default'}"
            onclick={onOpenMedia ? () => onOpenMedia(item.id) : undefined}
            disabled={!onOpenMedia}
          >
            <p
              class="flex items-center gap-1.5 text-[11px] font-semibold tracking-wide uppercase {isGem
                ? 'text-emerald-300'
                : 'text-rose-300'}"
            >
              {isGem ? "💎" : "💔"}
              {header}
            </p>
            <div class="flex items-center gap-3">
              {#if item.coverUrl}
                <img
                  src={item.coverUrl}
                  alt=""
                  class="h-20 w-14 shrink-0 rounded-md object-cover"
                  loading="lazy"
                />
              {:else}
                <div
                  class="flex h-20 w-14 shrink-0 items-center justify-center rounded-md bg-white/5"
                >
                  <Image class="size-5 text-slate-500" aria-hidden="true" />
                </div>
              {/if}
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-semibold text-white" title={item.title}>
                  {item.title}
                </p>
                <p class="mt-0.5 truncate text-xs text-slate-400">
                  {typeLabel(item.type)} · {hint}
                </p>
                <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
                  {#if userFirst}
                    <span class="font-bold text-amber-300">★ {item.userScore}</span>
                    <span class="text-slate-500">vs</span>
                    <span class="font-medium text-slate-300">★ {item.worldRating}</span>
                  {:else}
                    <span class="font-bold text-slate-300">★ {item.worldRating}</span>
                    <span class="text-slate-500">vs</span>
                    <span class="font-medium text-rose-300">★ {item.userScore}</span>
                  {/if}
                </div>
              </div>
            </div>
            <div class="flex items-center justify-between text-xs">
              <span class="text-slate-400">{i18n.t.stats.taste.divergenceBadge}</span>
              <span
                class="rounded-full border px-2.5 py-0.5 font-bold tabular-nums {deltaStyle(
                  item.delta,
                )}"
              >
                {deltaText(item.delta)}
              </span>
            </div>
          </button>
        {/if}
      {/each}
    </div>
    <p class="mt-3 text-[11px] text-slate-500">
      {i18n.t.stats.taste.yourScore} · {i18n.t.stats.taste.worldScore}
    </p>
  {/if}
</div>
