<script lang="ts">
    import { ArrowUpRight, History, LoaderCircle, RefreshCw, Trash2, Flag } from "$shared/ui/Icons.svelte";
    import {
        clearAllHistory,
        deleteHistoryEvent,
        errorMessage,
        getHistoryEvents,
    } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { HistoryEvent } from "$shared/types";
    import {
        formatHistoryEventLabel,
        HISTORY_EVENT_ICONS,
    } from "$shared/utils/historyFormatters";

    interface Props {
        refreshKey: number;
        onOpenMedia?: (mediaId: string) => void;
    }

    let { refreshKey, onOpenMedia }: Props = $props();

    let selectedDate = $state("");
    let events = $state<HistoryEvent[]>([]);
    let loading = $state(true);
    let loadError = $state<unknown>(null);
    let clearing = $state(false);
    let deletingId = $state<string | null>(null);
    let requestSequence = 0;

    $effect(() => {
        void refreshKey;
        void selectedDate;
        void loadEvents(++requestSequence);
    });

    async function loadEvents(sequence: number) {
        loading = true;
        loadError = null;

        try {
            const nextEvents = await getHistoryEvents({
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

    function formatDate(value: string): string {
        return new Intl.DateTimeFormat(i18n.current, {
            dateStyle: "medium",
            timeStyle: "short",
        }).format(new Date(value));
    }

    async function handleDeleteEvent(event: HistoryEvent) {
        if (deletingId !== null) return;
        if (!window.confirm(i18n.t.views.confirmDeleteHistoryEntry)) return;

        deletingId = event.id;
        // Drop the row immediately and restore it if the request fails, so the list never lags.
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

    async function handleClearAll() {
        if (events.length === 0) return;
        if (!window.confirm(i18n.t.views.confirmClearHistory)) return;

        clearing = true;
        const prevEvents = events;
        events = [];

        try {
            await clearAllHistory();
            showToast(i18n.t.views.historyCleared, "success");
        } catch (err) {
            events = prevEvents;
            showToast(errorMessage(err), "error");
        } finally {
            clearing = false;
        }
    }
</script>

<div class="mx-auto max-w-4xl space-y-6">
    <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
            <p
                class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
            >
                {i18n.t.library.collectionLabel}
            </p>
            <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">
                {i18n.t.views.historyTitle}
            </h2>
            <p class="mt-2 text-sm text-muted">{i18n.t.views.historyHint}</p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
            <div class="flex items-center gap-1.5">
                <input
                    type="date"
                    bind:value={selectedDate}
                    class="h-8 rounded-lg border border-white/10 bg-field px-2.5 text-xs text-white outline-none focus:border-accent focus:ring-1 focus:ring-accent transition cursor-pointer"
                    aria-label={i18n.t.views.filterByDate}
                />
                {#if selectedDate}
                    <button
                        type="button"
                        class="h-8 rounded-lg border border-white/10 bg-field px-2.5 text-xs text-muted hover:text-white transition cursor-pointer"
                        onclick={() => (selectedDate = "")}
                    >
                        {i18n.t.views.resetDate}
                    </button>
                {/if}
            </div>

            {#if events.length > 0}
                <button
                    type="button"
                    class="inline-flex items-center gap-1.5 rounded-md border border-white/10 bg-field px-3 py-1.5 text-xs font-semibold text-rose-400 transition hover:bg-rose-500/10 hover:border-rose-500/40 cursor-pointer disabled:opacity-50"
                    disabled={clearing}
                    onclick={handleClearAll}
                >
                    <Trash2 size={13} />
                    <span>{i18n.t.views.clearHistory}</span>
                </button>
            {/if}
        </div>
    </div>

    {#if loading}
        <div class="space-y-3" aria-hidden="true">
            {#each Array(4) as _, index (index)}
                <div class="h-16 animate-pulse rounded-lg bg-card"></div>
            {/each}
        </div>
        <p class="sr-only" role="status">{i18n.t.common.loading}</p>
    {:else if loadError}
        <div
            class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
        >
            <p class="text-sm text-rose-200" role="alert">
                {errorMessage(loadError)}
            </p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                onclick={retry}
            >
                <RefreshCw size={15} aria-hidden="true" />
                {i18n.t.common.retry}
            </button>
        </div>
    {:else if events.length === 0}
        <div
            class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-surface p-6 text-center"
        >
            <div
                class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted"
            >
                <History size={22} aria-hidden="true" />
            </div>
            <p class="text-sm text-muted">
                {selectedDate
                    ? i18n.t.views.noActivityForDate
                    : i18n.t.common.noData}
            </p>
        </div>
    {:else}
        <ol class="space-y-3">
            {#each events as event (event.id)}
                {@const Icon = HISTORY_EVENT_ICONS[event.type] ?? Flag}
                <li
                    class="group/list flex items-center gap-4 rounded-lg bg-card p-4 transition hover:bg-card/80"
                >
                    <div
                        class="grid h-10 w-10 shrink-0 place-items-center rounded-md bg-accent/15 text-accent-soft"
                    >
                        <Icon size={17} aria-hidden="true" />
                    </div>
                    <div class="min-w-0 flex-1">
                        {#if event.title && event.mediaId && event.type !== 'Deleted'}
                            <button
                                type="button"
                                class="truncate text-sm font-semibold text-ink hover:text-accent-soft hover:underline text-left cursor-pointer transition inline-flex items-center gap-1.5 group/link"
                                onclick={() => onOpenMedia?.(event.mediaId)}
                                title={i18n.current === 'ru' ? 'Перейти к медиа' : 'Go to media'}
                            >
                                <span>{event.title}</span>
                                <ArrowUpRight size={13} class="opacity-0 group-hover/list:opacity-100 transition text-accent-soft shrink-0" />
                            </button>
                        {:else}
                            <span class="truncate text-sm font-semibold text-muted">
                                {event.title ?? '—'}
                            </span>
                        {/if}
                        <p class="mt-1 text-xs text-muted">
                            {formatHistoryEventLabel(event)}
                        </p>
                    </div>
                    <div class="flex shrink-0 items-center gap-2">
                        <span
                            class="text-xs text-muted tabular-nums"
                            >{formatDate(event.createdAt)}</span
                        >
                        <button
                            type="button"
                            class="grid h-7 w-7 place-items-center rounded-md text-muted opacity-0 transition group-hover/list:opacity-100 hover:bg-rose-500/10 hover:text-rose-400 focus-visible:opacity-100 cursor-pointer disabled:opacity-40"
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
                    </div>
                </li>
            {/each}
        </ol>
    {/if}
</div>
