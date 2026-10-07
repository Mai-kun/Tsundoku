<script lang="ts">
    import { Sparkles } from "$shared/ui/Icons.svelte";

    interface GenreItem {
        genre: string;
        count: number;
        percentage: number;
    }

    interface Props {
        genres: GenreItem[];
    }

    let { genres = [] }: Props = $props();

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

    const displayGenres = $derived(genres.slice(0, 8));
</script>

<div class="bg-[#151a26] border border-white/5 rounded-xl p-5">
    <div class="flex items-center gap-2 mb-4">
        <Sparkles class="size-4 text-amber-400" aria-hidden="true" />
        <h3 class="text-base font-semibold tracking-tight text-white">
            Любимые жанры
        </h3>
    </div>

    <div class="h-3 w-full rounded-full overflow-hidden bg-white/5 flex">
        {#if displayGenres.length === 0}
            <div class="h-full w-full bg-white/10"></div>
        {:else}
            {#each displayGenres as item, index (item.genre)}
                <div
                    class="h-full first:rounded-l-full last:rounded-r-full"
                    style="width: {item.percentage}%; background-color: {PALETTE[index % PALETTE.length]};"
                    title="{item.genre}: {item.percentage}%"
                ></div>
            {/each}
        {/if}
    </div>

    {#if displayGenres.length > 0}
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 mt-4">
            {#each displayGenres as item, index (item.genre)}
                <div class="flex items-center gap-2 min-w-0">
                    <span
                        class="size-2.5 rounded-full shrink-0"
                        style="background-color: {PALETTE[index % PALETTE.length]};"
                    ></span>
                    <span class="text-sm font-medium text-slate-200 truncate" title={item.genre}>
                        {item.genre}
                    </span>
                    <span class="text-xs text-slate-400 tabular-nums shrink-0 ml-auto flex items-center gap-1">
                        <span>{item.count}</span>
                        <span class="rounded bg-white/5 px-1 py-0.5 text-[10px] text-slate-400">
                            {item.percentage}%
                        </span>
                    </span>
                </div>
            {/each}
        </div>
    {/if}
</div>
