<script lang="ts">
    import { List, Plus, Sparkles } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import { showToast } from "$shared/ui/toast.svelte";

    const placeholders = [
        {
            key: "watchlist",
            label: i18n.t.views.listsPresetWatchlist,
            tone: "text-sky-300",
        },
        {
            key: "season",
            label: i18n.t.views.listsPresetSeason,
            tone: "text-[#a5b4fc]",
        },
        {
            key: "favorites",
            label: i18n.t.views.listsPresetFavorites,
            tone: "text-amber-300",
        },
    ] as const;

    function createList() {
        showToast(i18n.t.views.listsCreateHint, "warning");
    }
</script>

<div class="mx-auto max-w-3xl space-y-6">
    <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
            <p
                class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
            >
                {i18n.t.library.collectionLabel}
            </p>
            <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">
                {i18n.t.views.listsTitle}
            </h2>
        </div>

        <button
            type="button"
            class="tap inline-flex items-center gap-2 rounded-lg border border-white/[0.08] bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:bg-accent-hover cursor-pointer"
            onclick={createList}
        >
            <Plus size={16} aria-hidden="true" />
            {i18n.t.views.listsCreate}
        </button>
    </div>

    <div class="grid gap-3 sm:grid-cols-3">
        {#each placeholders as list (list.key)}
            <button
                type="button"
                class="flex flex-col gap-3 rounded-xl border border-white/[0.06] bg-card p-5 text-left shadow-lg transition hover:border-indigo-500/30 cursor-pointer"
                onclick={createList}
            >
                <span
                    class="grid h-10 w-10 place-items-center rounded-lg border border-white/[0.06] bg-elevated {list.tone}"
                >
                    <List size={18} aria-hidden="true" />
                </span>
                <span class="text-sm font-semibold text-ink">{list.label}</span>
                <span class="text-xs text-muted"
                    >{i18n.t.common.comingSoon}</span
                >
            </button>
        {/each}
    </div>

    <div
        class="flex flex-col items-center justify-center rounded-xl border border-dashed border-white/[0.08] bg-card p-8 text-center sm:p-12"
    >
        <div
            class="grid h-14 w-14 place-items-center rounded-xl border border-white/[0.06] bg-elevated text-accent-soft"
        >
            <Sparkles size={24} aria-hidden="true" />
        </div>
        <p
            class="mt-5 text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
        >
            {i18n.t.common.comingSoon}
        </p>
        <p class="mt-3 max-w-md text-sm leading-6 text-muted">
            {i18n.t.views.listsHint}
        </p>
    </div>
</div>
