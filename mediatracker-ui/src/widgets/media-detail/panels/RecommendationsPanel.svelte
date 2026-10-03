<script lang="ts">
    import { Image as ImageIcon, LoaderCircle, RefreshCw, Sparkles } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { RecommendationItem } from "$widgets/media-detail/detailTypes";

    interface Props {
        items: readonly RecommendationItem[];
        loading: boolean;
        error: unknown;
        /** `force` skips the 30-day localStorage cache. */
        onLoad: (force?: boolean) => void;
    }

    let { items, loading, error, onLoad }: Props = $props();
</script>

<section class="space-y-4">
    <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
            <h2 class="text-sm font-bold uppercase tracking-wider text-slate-300">
                {i18n.t.detail.tabRecommendations}
            </h2>
            <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-lg border border-white/[0.08] bg-surface/50 px-2.5 py-1 text-xs font-medium text-slate-300 transition hover:bg-white/10 hover:text-white disabled:opacity-50 cursor-pointer"
                disabled={loading}
                onclick={() => onLoad(true)}
                title={i18n.current === "ru"
                    ? "Перезагрузить рекомендации"
                    : "Reload recommendations"}
            >
                <RefreshCw
                    size={13}
                    class={loading
                        ? "animate-spin text-[var(--color-success-line)]"
                        : "text-[var(--color-success-line)]"}
                />
                <span>{i18n.current === "ru" ? "Перезагрузить" : "Reload"}</span>
            </button>
        </div>
        <span class="text-xs text-muted">{i18n.t.detail.cachedForDays}</span>
    </div>

    {#if loading}
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
            {#each Array(5) as _, idx (idx)}
                <div class="space-y-2">
                    <div
                        class="aspect-[2/3] w-full animate-pulse rounded-lg bg-[var(--color-panel-line)]"
                    ></div>
                    <div
                        class="h-3 w-3/4 animate-pulse rounded bg-[var(--color-panel-line)]"
                    ></div>
                </div>
            {/each}
        </div>
    {:else if error}
        <div class="flex flex-col items-start gap-2 rounded-xl bg-rose-400/5 p-4">
            <p class="text-sm text-rose-200" role="alert">{errorMessage(error)}</p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md bg-accent px-3 py-1.5 text-xs font-medium text-white transition hover:bg-accent-hover"
                onclick={() => onLoad()}
            >
                <RefreshCw size={14} aria-hidden="true" />
                {i18n.t.common.retry}
            </button>
        </div>
    {:else if items.length === 0}
<!-- The only panel that must never auto-fetch: recommendations are requested
             strictly on this button. -->
        <div
            class="flex flex-col items-start gap-2 rounded-xl bg-[var(--color-panel-line)] p-5"
        >
            <p class="text-sm text-muted">{i18n.t.detail.noRecommendations}</p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md border border-[var(--color-accent)]/40 bg-[var(--color-accent)]/10 px-3 py-1.5 text-xs font-semibold text-[var(--color-accent-soft)] transition hover:bg-[var(--color-accent)]/20 disabled:opacity-40 cursor-pointer"
                disabled={loading}
                onclick={() => onLoad(true)}
            >
                {#if loading}
                    <LoaderCircle
                        size={13}
                        class="animate-spin"
                        aria-hidden="true"
                    />
                {:else}
                    <Sparkles size={13} aria-hidden="true" />
                {/if}
                {i18n.current === "ru"
                    ? "Получить рекомендации"
                    : "Get recommendations"}
            </button>
        </div>
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
                        <span>{rec.type}</span>
                        {#if rec.score}
                            <span class="font-bold text-amber-400"
                                >★ {rec.score.toFixed(1)}</span
                            >
                        {/if}
                    </div>
                </div>
            {/each}
        </div>
    {/if}
</section>