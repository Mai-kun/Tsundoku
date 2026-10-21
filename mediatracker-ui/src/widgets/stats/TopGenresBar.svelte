<script lang="ts">
    import { Sparkles } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";

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

    const PALETTE = ["#f59e0b", "#06b6d4", "#6366f1", "#f43f5e", "#3b82f6", "#ec4899", "#10b981", "#8b5cf6"];
    const categories = ["all", "game", "movie", "series", "anime", "manga", "book"] as const;
    const displayGenres = $derived((selectedType === "all" ? genres : genresByType[selectedType] ?? []).slice(0, 8));

    function genreLabel(genre: string): string {
        const normalized = genre.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
        const aliases: Record<string, string> = {
            "sci fi": "sciFi", "slice of life": "sliceOfLife", "game show": "gameShow", "talk show": "talkShow",
        };
        const key = aliases[normalized] ?? normalized.replace(/\s+([a-z])/g, (_, letter: string) => letter.toUpperCase()).replace(/^([a-z])/, (_, letter: string) => letter.toLowerCase());
        return key in i18n.t.stats.genres
            ? i18n.t.stats.genres[key as keyof typeof i18n.t.stats.genres]
            : genre;
    }
</script>

<div class="bg-[#151a26] border border-white/5 rounded-xl p-5">
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <div class="flex items-center gap-2">
            <Sparkles class="size-4 text-amber-400" aria-hidden="true" />
            <h3 class="text-base font-semibold tracking-tight text-white">{i18n.t.stats.topGenres}</h3>
        </div>
        <div class="grid w-full grid-cols-4 sm:grid-cols-7 gap-1 rounded-lg bg-white/[0.03] p-1" role="group" aria-label={i18n.t.stats.topGenres}>
            {#each categories as category (category)}
                <button
                    type="button"
                    aria-pressed={selectedType === category}
                    class="flex h-8 w-full items-center justify-center whitespace-nowrap rounded-md px-1 text-center text-xs font-medium transition-colors duration-200 {selectedType === category ? 'bg-[#5844e0]/30 text-white' : 'text-slate-400 hover:text-white'}"
                    onclick={() => (selectedType = category)}
                >
                    {i18n.t.stats.genreCategories[category]}
                </button>
            {/each}
        </div>
    </div>

    <div class="h-3 w-full rounded-full overflow-hidden bg-white/5 flex transition-all duration-300">
        {#if displayGenres.length === 0}
            <div class="h-full w-full bg-white/5"></div>
        {:else}
            {#each displayGenres as item, index (item.genre)}
                <div
                    class="h-full first:rounded-l-full last:rounded-r-full transition-[width,background-color] duration-300"
                    style="width: {item.percentage}%; background-color: {PALETTE[index % PALETTE.length]};"
                    title="{genreLabel(item.genre)}: {item.percentage}%"
                ></div>
            {/each}
        {/if}
    </div>

    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 mt-4 min-h-[104px] content-start transition-all duration-200">
        {#if displayGenres.length === 0}
            <div class="col-span-full flex items-center justify-center min-h-[104px] text-xs text-muted">
                {i18n.current === 'ru' ? 'Нет данных о жанрах в этой категории' : 'No genre data for this category'}
            </div>
        {:else}
            {#each displayGenres as item, index (item.genre)}
                <div class="flex items-center gap-2 min-w-0">
                    <span class="size-2.5 rounded-full shrink-0" style="background-color: {PALETTE[index % PALETTE.length]};"></span>
                    <span class="text-sm font-medium text-slate-200 truncate" title={genreLabel(item.genre)}>{genreLabel(item.genre)}</span>
                    <span class="text-xs text-slate-400 tabular-nums shrink-0 ml-auto flex items-center gap-1">
                        <span>{item.count}</span>
                        <span class="rounded bg-white/5 px-1 py-0.5 text-[10px] text-slate-400">{item.percentage}%</span>
                    </span>
                </div>
            {/each}
        {/if}
    </div>
</div>
