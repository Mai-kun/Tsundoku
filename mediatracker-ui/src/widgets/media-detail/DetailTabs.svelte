<script lang="ts">
    import { Sparkles } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { SubTab } from "./detailTypes";

    interface Props {
        active: SubTab;
        mediaType: string;
        /** Undefined for non-shows; drives the "3/12" badge on the episodes tab. */
        seasonProgress: { current: number; total: number | null } | null;
        relatedCount: number;
        onSelect: (tab: SubTab) => void;
    }

    let {
        active,
        mediaType,
        seasonProgress,
        relatedCount,
        onSelect,
    }: Props = $props();

    function tabClass(tab: SubTab): string {
        return `flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
            active === tab
                ? "border-[var(--color-accent)] text-white"
                : "border-transparent text-muted hover:text-white"
        }`;
    }
</script>

<nav class="flex items-center gap-1 border-b border-white/[0.08] pb-px" aria-label="Sections">
    <button
        type="button"
        class={tabClass("overview")}
        onclick={() => onSelect("overview")}
    >
        {i18n.t.detail.tabOverview}
    </button>

    {#if mediaType === "tvshow"}
        <button
            type="button"
            class={tabClass("episodes")}
            onclick={() => onSelect("episodes")}
        >
            {i18n.t.detail.tabEpisodes}
            {#if seasonProgress}
                <span
                    class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-[var(--color-accent-soft)]"
                >
                    {seasonProgress.current}/{seasonProgress.total}
                </span>
            {/if}
        </button>
    {/if}

    <button
        type="button"
        class={tabClass("related")}
        onclick={() => onSelect("related")}
    >
        {i18n.t.detail.tabRelatedMedia}
        {#if relatedCount > 0}
            <span class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-muted">
                {relatedCount}
            </span>
        {/if}
    </button>

    <button
        type="button"
        class={tabClass("recommendations")}
        onclick={() => {
            // No fetch here: the tab renders the recommendations already stored on the row.
            onSelect("recommendations");
        }}
    >
        <Sparkles
            size={14}
            class="text-[var(--color-accent-soft)]"
            aria-hidden="true"
        />
        {i18n.t.detail.tabRecommendations}
    </button>
</nav>