<script lang="ts">
  import { Sparkles } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import { genreLabel } from "$entities/media/model/genreLabel";

  interface GenreItem {
    genre: string;
    count: number;
    percentage: number;
  }

  interface Props {
    genres: GenreItem[];
    genresByType?: Record<string, GenreItem[]>;
  }

  let { genres = [], genresByType = {} }: Props = $props();
  let selectedType = $state<string>("all");

  const PALETTE = [
    "#f59e0b",
    "#06b6d4",
    "#6366f1",
    "#f43f5e",
    "#3b82f6",
    "#ec4899",
    "#10b981",
    "#8b5cf6",
  ];
  const categories = ["all", "game", "movie", "series", "anime", "manga", "book"] as const;
  const displayGenres = $derived(
    (selectedType === "all" ? genres : (genresByType[selectedType] ?? [])).slice(0, 8),
  );
</script>

<div class="rounded-xl border border-white/5 bg-[#151a26] p-5">
  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <div class="flex items-center gap-2">
      <Sparkles class="size-4 text-amber-400" aria-hidden="true" />
      <h3 class="text-base font-semibold tracking-tight text-white">{i18n.t.stats.topGenres}</h3>
    </div>
    <div
      class="grid w-full grid-cols-4 gap-1 rounded-lg bg-white/[0.03] p-1 sm:grid-cols-7"
      role="group"
      aria-label={i18n.t.stats.topGenres}
    >
      {#each categories as category (category)}
        <button
          type="button"
          aria-pressed={selectedType === category}
          class="flex h-8 w-full items-center justify-center rounded-md px-1 text-center text-xs font-medium whitespace-nowrap transition-colors duration-200 {selectedType ===
          category
            ? 'bg-[#5844e0]/30 text-white'
            : 'text-slate-400 hover:text-white'}"
          onclick={() => (selectedType = category)}
        >
          {i18n.t.stats.genreCategories[category]}
        </button>
      {/each}
    </div>
  </div>

  <div class="flex h-3 w-full overflow-hidden rounded-full bg-white/5 transition duration-300">
    {#if displayGenres.length === 0}
      <div class="h-full w-full bg-white/5"></div>
    {:else}
      {#each displayGenres as item, index (item.genre)}
        <div
          class="h-full transition-[width,background-color] duration-300 first:rounded-l-full last:rounded-r-full"
          style="width: {item.percentage}%; background-color: {PALETTE[index % PALETTE.length]};"
          title="{genreLabel(item.genre)}: {item.percentage}%"
        ></div>
      {/each}
    {/if}
  </div>

  <div
    class="mt-4 grid min-h-[104px] grid-cols-2 content-start gap-3 transition-[width] duration-200 sm:grid-cols-3 md:grid-cols-4"
  >
    {#if displayGenres.length === 0}
      <div class="text-muted col-span-full flex min-h-[104px] items-center justify-center text-xs">
        {i18n.current === "ru"
          ? "Нет данных о жанрах в этой категории"
          : "No genre data for this category"}
      </div>
    {:else}
      {#each displayGenres as item, index (item.genre)}
        <div class="flex min-w-0 items-center gap-2">
          <span
            class="size-2.5 shrink-0 rounded-full"
            style="background-color: {PALETTE[index % PALETTE.length]};"
          ></span>
          <span class="truncate text-sm font-medium text-slate-200" title={genreLabel(item.genre)}
            >{genreLabel(item.genre)}</span
          >
          <span
            class="ml-auto flex shrink-0 items-center gap-1 text-xs text-slate-400 tabular-nums"
          >
            <span>{item.count}</span>
            <span class="rounded bg-white/5 px-1 py-0.5 text-[10px] text-slate-400"
              >{item.percentage}%</span
            >
          </span>
        </div>
      {/each}
    {/if}
  </div>
</div>
