<script lang="ts">
    import { ChevronDown, LoaderCircle, Sparkles } from "$shared/ui/Icons.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
    import { errorMessage, getSources } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaType, SourceInfo } from "$shared/types";

    interface Props {
        isOpen: boolean;
        busy: boolean;
        mediaType: MediaType | string;
        currentSource?: string | null;
        onFill: (source: string) => void;
        onClose: () => void;
    }

    let {
        isOpen,
        busy,
        mediaType,
        currentSource = null,
        onFill,
        onClose,
    }: Props = $props();

    let sources = $state<SourceInfo[]>([]);
    let source = $state("");
    let loadError = $state<string | null>(null);

    $effect(() => {
        if (!isOpen || sources.length > 0) return;
        let cancelled = false;
        void getSources()
            .then((list) => {
                if (!cancelled) sources = list.filter((s) => s.isEnabled);
            })
            .catch((error) => {
                if (!cancelled) loadError = errorMessage(error);
            });
        return () => {
            cancelled = true;
        };
    });

    // Preselect what the item already points at: topping up gaps in the same provider is the
    // common case, and re-picking it every time is pure friction.
    $effect(() => {
        if (isOpen && source === "") source = currentSource ?? "";
    });

    const options = $derived(
        sources.map((entry) => ({ value: entry.id, label: entry.name })),
    );

    const selectedLabel = $derived(
        options.find((o) => o.value === source)?.label ??
            options.find((o) => o.value === currentSource)?.label ??
            options[0]?.label ??
            "",
    );
</script>

<Modal {isOpen} onClose={onClose} labelledBy="fill-missing-title">
    <div class="p-5">
        <h2
            id="fill-missing-title"
            class="inline-flex items-center gap-2 text-base font-semibold text-white"
        >
            <Sparkles
                size={16}
                class="text-[var(--color-accent-soft)]"
                aria-hidden="true"
            />
            {i18n.t.detail.fillMissingTitle}
        </h2>
        <p class="mt-1.5 text-sm text-muted">
            {i18n.t.detail.fillMissingHint}
        </p>
    </div>

    <div class="border-t border-white/[0.08] p-5">
        <div class="flex items-center justify-between gap-3">
            <span class="shrink-0 text-xs font-medium text-muted">
                {i18n.t.detail.fillMissingSource}
            </span>
            <div class="min-w-0 flex-1 text-right">
                {#if options.length > 0}
                    <PopoverMenu
                        id={`fill-missing-${mediaType}`}
                        {options}
                        selected={source}
                        onSelect={(value) => (source = String(value))}
                        label={i18n.t.detail.fillMissingSource}
                        placement="bottom-end"
                        class="max-h-56 min-w-[180px] overflow-y-auto"
                        optionClass="text-xs"
                        openOnHover
                        closeDelay={220}
                    >
                        {#snippet trigger({ popoverTargetId, anchorName })}
                            <button
                                type="button"
                                popovertarget={popoverTargetId}
                                popovertargetaction="toggle"
                                style="anchor-name: {anchorName}"
                                class="tap flex max-w-[220px] items-center justify-between gap-2 rounded-lg border border-white/[0.08] bg-[var(--color-field)] px-2.5 py-1.5 text-xs text-white transition hover:bg-[var(--color-track-faint)] has-[:popover-open]:ring-1 has-[:popover-open]:ring-[var(--color-accent)]"
                                aria-haspopup="listbox"
                            >
                                <span class="truncate">{selectedLabel}</span>
                                <ChevronDown
                                    size={13}
                                    class="shrink-0 text-muted transition duration-200 has-[:popover-open]:rotate-180 has-[:popover-open]:text-white"
                                    aria-hidden="true"
                                />
                            </button>
                        {/snippet}
                    </PopoverMenu>
                {:else}
                    <span class="text-xs text-muted">—</span>
                {/if}
            </div>
        </div>
    </div>

    {#if loadError}
        <p class="px-5 pb-3 text-xs text-rose-300" role="alert">
            {i18n.t.detail.fillMissingSourcesFailed}
        </p>
    {/if}

    <div class="flex gap-2 border-t border-white/[0.08] p-5">
        <button
            type="button"
            class="tap inline-flex flex-1 items-center justify-center gap-2 rounded-lg bg-[var(--color-accent)] px-4 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-accent-hover)] disabled:cursor-wait disabled:opacity-60"
            disabled={busy || options.length === 0}
            onclick={() => onFill(source || options[0]?.value || "")}
        >
            {#if busy}
                <LoaderCircle size={14} class="animate-spin" aria-hidden="true" />
                {i18n.t.detail.fillMissingRunning}
            {:else}
                {i18n.t.detail.fillMissing}
            {/if}
        </button>
        <button
            type="button"
            class="tap rounded-lg px-4 py-2.5 text-sm text-muted transition hover:text-white disabled:opacity-60"
            disabled={busy}
            onclick={onClose}
        >
            {i18n.t.common.cancel}
        </button>
    </div>
</Modal>