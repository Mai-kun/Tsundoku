<script lang="ts">
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import { LayoutGrid, List } from "$shared/ui/Icons.svelte";

    /** Icon-only compact/large toggle for the people cards; mirrored in CastSection and CreatorSection. */
    const isLarge = $derived(uiSettings.peopleCardSize === "large");
</script>

<div class="inline-flex items-center rounded-lg border border-white/[0.08] bg-white/[0.03] p-0.5 gap-0.5">
    <button
        type="button"
        class="grid size-6 place-items-center rounded-md transition cursor-pointer
               {isLarge ? 'text-muted hover:text-white' : 'bg-accent text-white'}"
        onclick={() => uiSettings.setPeopleCardSize("compact")}
        title={i18n.t.detail.compactViewTooltip}
        aria-label={i18n.t.detail.compactViewTooltip}
        aria-pressed={!isLarge}
    >
        <List size={14} />
    </button>
    <button
        type="button"
        class="grid size-6 place-items-center rounded-md transition cursor-pointer
               {isLarge ? 'bg-accent text-white' : 'text-muted hover:text-white'}"
        onclick={() => uiSettings.setPeopleCardSize("large")}
        title={i18n.t.detail.largeViewTooltip}
        aria-label={i18n.t.detail.largeViewTooltip}
        aria-pressed={isLarge}
    >
        <LayoutGrid size={14} />
    </button>
</div>
