<script lang="ts">
    import { Image as ImageIcon } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { RecommendationItem } from "../detailTypes";

    interface Props {
        /** The ready-made `media.recommendations`: this tab only renders it — no source picker. */
        items: readonly RecommendationItem[];
    }

    let { items }: Props = $props();
</script>

{#if items.length === 0}
    <p class="text-sm text-muted">{i18n.t.detail.noRecommendations}</p>
{:else}
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
        {#each items as rec (rec.id)}
            <div class="group flex flex-col items-start text-left">
                <div
                    class="aspect-[2/3] w-full overflow-hidden rounded-lg bg-[var(--color-panel-line)] transition group-hover:ring-2 group-hover:ring-[var(--color-accent)]"
                >
                    {#if rec.coverUrl}
                        <img
                            src={rec.coverUrl}
                            alt={rec.title}
                            class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
                        />
                    {:else}
                        <div class="grid h-full place-items-center text-muted">
                            <ImageIcon
                                size={24}
                                stroke-width={1.25}
                                aria-hidden="true"
                            />
                        </div>
                    {/if}
                </div>
                <span
                    class="mt-1.5 line-clamp-1 text-xs font-semibold text-white group-hover:text-[var(--color-accent-soft)]"
                    >{rec.title}</span
                >
                <div
                    class="flex items-center justify-between w-full mt-0.5 text-[11px] text-muted"
                >
                    <span>{rec.source}</span>
                    {#if rec.rating}
                        <span class="font-bold text-amber-400"
                            >★ {rec.rating.toFixed(1)}</span
                        >
                    {/if}
                </div>
            </div>
        {/each}
    </div>
{/if}
