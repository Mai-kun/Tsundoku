<script lang="ts">
    import { History, LoaderCircle, RefreshCw, X, Trash2 } from "$shared/ui/Icons.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import { deleteHistoryEvent, errorMessage, getHistoryEvents } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { HistoryEvent } from "$shared/types";
    import {
        formatHistoryDate,
        formatHistoryEventLabel,
        formatHistoryTime,
        HISTORY_EVENT_ICONS,
    } from "$shared/utils/historyFormatters";

    interface Props {
        isOpen: boolean;
        mediaId: string;
        title: string;
        onClose: () => void;
    }

    let { isOpen, mediaId, title, onClose }: Props = $props();

    let selectedDate = $state("");
    let events = $state<HistoryEvent[]>([]);
    let loading = $state(false);
    let loadError = $state<unknown>(null);
    let deletingId = $state<string | null>(null);
    let requestSequence = 0;

    $effect(() => {
        if (!isOpen || !mediaId) {
            return;
        }
        void loadEvents(++requestSequence);
    });

    async function loadEvents(sequence: number) {
        loading = true;
        loadError = null;

        try {
            const nextEvents = await getHistoryEvents({
                mediaId,
                date: selectedDate || undefined,
            });
            if (sequence === requestSequence) {
                events = nextEvents;
            }
        } catch (error) {
            if (sequence === requestSequence) {
                loadError = error;
            }
        } finally {
            if (sequence === requestSequence) {
                loading = false;
            }
        }
    }

    function retry() {
        void loadEvents(++requestSequence);
    }

    async function handleDeleteEvent(event: HistoryEvent) {
        if (deletingId !== null) return;
        if (!window.confirm(i18n.t.views.confirmDeleteHistoryEntry)) return;

        deletingId = event.id;
        const prevEvents = events;
        events = events.filter((x) => x.id !== event.id);

        try {
            await deleteHistoryEvent(event.id);
            showToast(i18n.t.views.historyEntryDeleted, "success");
        } catch (err) {
            events = prevEvents;
            showToast(errorMessage(err), "error");
        } finally {
            deletingId = null;
        }
    }
</script>

<Modal {isOpen} {onClose} labelledBy="media-activity-title">
    <div class="flex max-h-[75vh] flex-col">
        <header
            class="flex items-center gap-3 border-b border-white/[0.08] px-5 py-4 shrink-0"
        >
            <History
                size={18}
                class="shrink-0 text-[var(--color-accent-soft)]"
                aria-hidden="true"
            />
            <div class="min-w-0 flex-1">
                <h2 id="media-activity-title" class="text-sm font-bold text-white">
                    {i18n.t.views.historyTitle}
                </h2>
                <p class="truncate text-xs text-muted">
                    {title}
                </p>
            </div>
            <button
                type="button"
                class="ml-auto shrink-0 rounded-md p-1.5 text-muted transition hover:bg-white/5 hover:text-white cursor-pointer"
                aria-label={i18n.t.common.close}
                onclick={onClose}
            >
                <X size={16} aria-hidden="true" />
            </button>
        </header>

        <!-- Date filter bar -->
        <div
            class="flex flex-wrap items-center justify-between gap-3 border-b border-white/[0.08] bg-surface/30 px-5 py-3 shrink-0"
        >
            <div class="flex items-center gap-2">
                <span class="text-xs text-muted font-medium"
                    >{i18n.t.views.filterByDate}:</span
                >
                <input
                    type="date"
                    bind:value={selectedDate}
                    class="bg-field border border-white/10 rounded-lg px-3 py-1.5 text-xs text-white outline-none focus:border-accent focus:ring-1 focus:ring-accent transition cursor-pointer"
                />
                {#if selectedDate}
                    <button
                        type="button"
                        class="rounded-lg border border-white/10 bg-field px-2.5 py-1.5 text-xs text-muted hover:text-white transition cursor-pointer"
                        onclick={() => (selectedDate = "")}
                    >
                        {i18n.t.views.resetDate}
                    </button>
                {/if}
            </div>
        </div>

        <!-- Activity list -->
        <div class="flex-1 overflow-y-auto p-5 min-h-[220px]">
            {#if loading}
                <div class="space-y-3" aria-hidden="true">
                    {#each Array(3) as _, index (index)}
                        <div class="h-14 animate-pulse rounded-lg bg-card"></div>
                    {/each}
                </div>
                <p class="sr-only" role="status">{i18n.t.common.loading}</p>
            {:else if loadError}
                <div
                    class="flex min-h-48 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
                >
                    <p class="text-sm text-rose-200" role="alert">
                        {errorMessage(loadError)}
                    </p>
                    <button
                        type="button"
                        class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-xs font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                        onclick={retry}
                    >
                        <RefreshCw size={14} aria-hidden="true" />
                        {i18n.t.common.retry}
                    </button>
                </div>
            {:else if events.length === 0}
                <div
                    class="flex min-h-48 flex-col items-center justify-center gap-3 rounded-lg bg-surface/50 p-6 text-center"
                >
                    <div
                        class="grid h-10 w-10 place-items-center rounded-lg bg-card text-muted"
                    >
                        <History size={20} aria-hidden="true" />
                    </div>
                    <p class="text-xs text-muted">
                        {selectedDate
                            ? i18n.t.views.noActivityForDate
                            : i18n.t.views.noActivity}
                    </p>
                </div>
            {:else}
                <ol class="space-y-2.5">
                    {#each events as event (event.id)}
                        {@const Icon = HISTORY_EVENT_ICONS[event.type] ?? History}
                        <li
                            class="group/item flex items-center gap-3.5 rounded-lg border border-white/5 bg-card/60 p-3 transition hover:bg-card"
                        >
                            <div
                                class="grid h-9 w-9 shrink-0 place-items-center rounded-md bg-accent/15 text-accent-soft"
                            >
                                <Icon size={16} aria-hidden="true" />
                            </div>
                            <div class="min-w-0 flex-1">
                                <p class="text-xs font-semibold text-ink">
                                    {formatHistoryEventLabel(event)}
                                </p>
                                <p class="mt-0.5 text-[11px] text-muted flex items-center gap-1.5">
                                    <span class="tabular-nums font-medium text-white/80"
                                        >{formatHistoryTime(event.createdAt)}</span
                                    >
                                    <span>·</span>
                                    <span>{formatHistoryDate(event.createdAt)}</span>
                                </p>
                            </div>
                            <button
                                type="button"
                                class="grid h-7 w-7 shrink-0 place-items-center rounded-md text-muted opacity-0 transition group-hover/item:opacity-100 hover:bg-rose-500/10 hover:text-rose-400 focus-visible:opacity-100 cursor-pointer disabled:opacity-40"
                                disabled={deletingId !== null}
                                aria-label={i18n.t.views.confirmDeleteHistoryEntry}
                                title={i18n.t.views.confirmDeleteHistoryEntry}
                                onclick={() => void handleDeleteEvent(event)}
                            >
                                {#if deletingId === event.id}
                                    <LoaderCircle
                                        size={13}
                                        class="animate-spin"
                                        aria-hidden="true"
                                    />
                                {:else}
                                    <Trash2 size={13} aria-hidden="true" />
                                {/if}
                            </button>
                        </li>
                    {/each}
                </ol>
            {/if}
        </div>
    </div>
</Modal>
