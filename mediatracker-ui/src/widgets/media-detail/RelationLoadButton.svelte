<script lang="ts">
    import { ChevronDown, Link2, LoaderCircle } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
    import {
        availableRelationSources,
        type RelationSourceOption,
    } from "$widgets/media-detail/relationSources";

    interface Props {
        media: { type: string; isAnime?: boolean };
        loading: boolean;
        /** "related" reads "Загрузить связанные", "recommendations" reads "Получить рекомендации". */
        kind: "related" | "recommendations";
        /** The provider the currently shown data came from; it stays selectable, not locked. */
        currentSource?: string | null;
        /** Picking an option loads from it; `force` skips the 30-day cache. */
        onLoad: (source: string, force?: boolean) => void;
    }

    let { media, loading, kind, currentSource = null, onLoad }: Props = $props();

    let sources = $state<RelationSourceOption[]>([]);
    let selected = $state("");
    let resolved = $state(false);

    // The list depends on the user's settings and on the media type, so it is resolved once per item
    // rather than on every render.
    $effect(() => {
        const key = `${media.type}:${media.isAnime ?? false}`;
        if (resolved) return;
        resolved = true;
        void availableRelationSources(media).then((list) => {
            sources = list;
            // Open on the provider that produced what is already on screen, so the label does not
            // jump to the first entry the moment the panel renders.
            selected =
                list.find((source) => matches(source, currentSource))?.id ??
                list[0]?.id ??
                "";
        });
    });

    // The stored source is a display name ("MangaDex") while the option carries an id ("mangadex").
    function matches(source: RelationSourceOption, wanted: string | null | undefined) {
        if (!wanted) return false;
        const needle = wanted.toLowerCase();
        return (
            source.id.toLowerCase() === needle || source.label.toLowerCase() === needle
        );
    }

    const selectedLabel = $derived(
        sources.find((source) => source.id === selected)?.label ??
            currentSource ??
            (i18n.current === "ru" ? "Выберите источник" : "Choose a source"),
    );

    /** The menu works in {value,label} pairs; a relation source is stored as an {id,label}. */
    const options = $derived(
        sources.map((source) => ({ value: source.id, label: source.label })),
    );

    const label = $derived(
        i18n.current === "ru"
            ? kind === "related"
                ? "Загрузить связанные"
                : "Получить рекомендации"
            : kind === "related"
              ? "Load related"
              : "Get recommendations",
    );
</script>

<!-- Steam Deck greys: #1c202b is the shell colour, the popover menu sits one step lighter on top. -->
<div class="flex flex-wrap items-center gap-2">
    <PopoverMenu
        id="relation-source"
        {options}
        {selected}
        onSelect={(value) => {
            if (typeof value === "string" && value !== selected) {
                // The label has to flip on the click itself. Only awaiting onLoad left the trigger
                // showing the old source (and the check mark on it) while the request was already
                // in flight, so a failing MangaDex pick looked like "nothing happened".
                selected = value;
                onLoad(value, true);
            }
        }}
        class="min-w-44 border-white/10 bg-[#262b3a]!"
        placement="bottom-end"
        optionClass="text-slate-200 hover:bg-white/[0.07]"
        label={i18n.current === "ru" ? "Источник связанных" : "Related source"}
    >
        {#snippet trigger({ popoverTargetId, anchorName })}
            <button
                type="button"
                popovertarget={popoverTargetId}
                popovertargetaction="toggle"
                style="anchor-name: {anchorName}"
                disabled={loading || sources.length === 0}
                aria-haspopup="listbox"
                aria-label={i18n.current === "ru"
                    ? "Источник связанных"
                    : "Related source"}
                class="tap inline-flex h-8 items-center gap-2 rounded-md border border-white/[0.08] bg-[#1c202b] px-2.5 text-xs font-semibold text-slate-200 transition hover:border-accent/40 hover:text-white disabled:cursor-not-allowed disabled:opacity-40 has-[:popover-open]:border-accent/50 has-[:popover-open]:text-white"
            >
                <Link2
                    size={13}
                    class="shrink-0 text-[var(--color-accent-soft)]"
                    aria-hidden="true"
                />
                <span class="truncate">
                    {i18n.current === "ru" ? "Источник" : "Source"}: {selectedLabel}
                </span>
                {#if loading}
                    <LoaderCircle
                        size={13}
                        class="shrink-0 animate-spin text-[var(--color-success-line)]"
                        aria-hidden="true"
                    />
                {/if}
                <ChevronDown size={13} class="shrink-0 text-slate-400" aria-hidden="true" />
            </button>
        {/snippet}
    </PopoverMenu>

    <button
        type="button"
        class="inline-flex h-8 items-center gap-2 rounded-md border border-[var(--color-accent)]/40 bg-[var(--color-accent)]/10 px-3 text-xs font-semibold text-[var(--color-accent-soft)] transition hover:bg-[var(--color-accent)]/20 disabled:opacity-40"
        disabled={loading || !selected}
        onclick={() => selected && onLoad(selected)}
    >
        {#if loading}
            <LoaderCircle size={13} class="animate-spin" aria-hidden="true" />
        {/if}
        {loading ? (i18n.current === "ru" ? "Загрузка…" : "Loading…") : label}
    </button>
</div>