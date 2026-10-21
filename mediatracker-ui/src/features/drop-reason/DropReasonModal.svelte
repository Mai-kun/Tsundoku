<script lang="ts">
    import { Ban, Trash2, X } from "$shared/ui/Icons.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import { updateStatus, errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import { MEDIA_STATUS } from "$shared/types";
    import {
        getDropReasonsForMediaType,
        type DropReasonOption,
    } from "$entities/media/model/dropReasons";
    import {
        dropPromptState,
        type DropPromptTarget,
    } from "./dropReasonPrompt.svelte";

    interface Props {
        target?: DropPromptTarget | null;
        isOpen?: boolean;
        onClose?: () => void;
    }

    let {
        target: explicitTarget = null,
        isOpen: explicitIsOpen,
        onClose: explicitOnClose,
    }: Props = $props();

    const currentTarget = $derived(explicitTarget ?? dropPromptState.target);
    const isOpen = $derived(
        explicitIsOpen !== undefined
            ? explicitIsOpen
            : currentTarget !== null,
    );

    let selectedReason = $state<string | null>(null);
    let notes = $state("");
    let saving = $state(false);
    let saveError = $state<unknown>(null);

    $effect(() => {
        if (currentTarget) {
            selectedReason = currentTarget.dropReason ?? null;
            notes = currentTarget.dropNotes ?? "";
            saveError = null;
        }
    });

    const isRu = $derived(i18n.current === "ru");
    const options = $derived<DropReasonOption[]>(
        currentTarget
            ? getDropReasonsForMediaType(currentTarget.type, currentTarget.isAnime)
            : [],
    );

    function close() {
        if (explicitOnClose) {
            explicitOnClose();
        } else {
            dropPromptState.close();
        }
    }

    function handleSkip() {
        if (saving) return;
        close();
    }

    async function handleSave() {
        if (!currentTarget || saving) return;
        saving = true;
        saveError = null;
        try {
            const cleanNotes = notes.trim() || null;
            await updateStatus(currentTarget.id, {
                status: MEDIA_STATUS.dropped,
                dropReason: selectedReason,
                dropNotes: cleanNotes,
            });
            currentTarget.onSaved?.(selectedReason, cleanNotes);
            close();
        } catch (e) {
            saveError = e;
        } finally {
            saving = false;
        }
    }

    async function handleDeleteReason() {
        if (!currentTarget || saving) return;
        saving = true;
        saveError = null;
        try {
            await updateStatus(currentTarget.id, {
                status: MEDIA_STATUS.dropped,
                dropReason: "",
                dropNotes: "",
            });
            currentTarget.onSaved?.(null, null);
            close();
        } catch (e) {
            saveError = e;
        } finally {
            saving = false;
        }
    }

    function toggleReason(key: string) {
        selectedReason = selectedReason === key ? null : key;
    }
</script>

{#if isOpen && currentTarget}
    <Modal {isOpen} onClose={handleSkip} size="md">
        <div class="flex flex-col p-6 space-y-5">
            <!-- Header -->
            <div class="flex items-start justify-between gap-3">
                <div class="flex items-center gap-3">
                    <div class="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-rose-500/10 text-rose-400 border border-rose-500/20">
                        <Ban size={20} aria-hidden="true" />
                    </div>
                    <div class="min-w-0">
                        <h2 class="text-base font-semibold text-white tracking-tight">
                            {i18n.t.dropReason.modalTitle}
                        </h2>
                        <p class="text-xs text-slate-400 truncate max-w-sm" title={currentTarget.title}>
                            {currentTarget.title}
                        </p>
                    </div>
                </div>
                <button
                    type="button"
                    class="tap -mr-2 -mt-2 p-2 rounded-lg text-slate-400 hover:text-white transition hover:bg-white/5"
                    onclick={handleSkip}
                    aria-label={i18n.t.dropReason.skip}
                >
                    <X size={18} aria-hidden="true" />
                </button>
            </div>

            <!-- Chips container -->
            <div class="space-y-2">
                <div class="flex flex-wrap gap-2 max-h-56 overflow-y-auto pr-1">
                    {#each options as option (option.key)}
                        {@const active = selectedReason === option.key}
                        <button
                            type="button"
                            class="tap text-xs px-3 py-1.5 rounded-lg border transition cursor-pointer {active
                                ? 'bg-rose-500/20 text-rose-300 border-rose-500/40 ring-1 ring-rose-500/30 font-medium'
                                : 'bg-white/[0.04] text-slate-300 border-white/[0.08] hover:bg-white/[0.08] hover:text-white'}"
                            onclick={() => toggleReason(option.key)}
                        >
                            {isRu ? option.label.ru : option.label.en}
                        </button>
                    {/each}
                </div>
            </div>

            <!-- Note input -->
            <div class="space-y-1.5">
                <input
                    type="text"
                    bind:value={notes}
                    placeholder={i18n.t.dropReason.notesPlaceholder}
                    maxlength={200}
                    class="w-full rounded-lg border border-white/[0.08] bg-white/[0.03] px-3.5 py-2 text-xs text-white placeholder-slate-500 focus:border-rose-400/50 focus:outline-none focus:ring-1 focus:ring-rose-400/30"
                    onkeydown={(e) => {
                        if (e.key === "Enter") {
                            e.preventDefault();
                            void handleSave();
                        }
                    }}
                />
            </div>

            {#if saveError}
                <p class="text-xs text-rose-400" role="alert">
                    {errorMessage(saveError)}
                </p>
            {/if}

            <!-- Footer actions -->
            <div class="flex items-center justify-between gap-3 pt-1 border-t border-white/5">
                <div>
                    {#if currentTarget.dropReason}
                        <button
                            type="button"
                            class="tap inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-rose-400/80 hover:text-rose-300 hover:bg-rose-500/10 rounded-lg transition"
                            onclick={handleDeleteReason}
                            disabled={saving}
                        >
                            <Trash2 size={13} aria-hidden="true" />
                            {i18n.t.dropReason.deleteReason}
                        </button>
                    {/if}
                </div>

                <div class="flex items-center gap-2">
                    <button
                        type="button"
                        class="tap px-3.5 py-1.5 text-xs font-medium text-slate-300 hover:text-white hover:bg-white/5 rounded-lg transition"
                        onclick={handleSkip}
                        disabled={saving}
                    >
                        {i18n.t.dropReason.skip}
                    </button>
                    <button
                        type="button"
                        class="tap px-4 py-1.5 text-xs font-semibold text-white bg-rose-600 hover:bg-rose-500 disabled:opacity-50 rounded-lg shadow-md transition"
                        onclick={handleSave}
                        disabled={saving}
                    >
                        {saving ? "..." : i18n.t.dropReason.save}
                    </button>
                </div>
            </div>
        </div>
    </Modal>
{/if}
