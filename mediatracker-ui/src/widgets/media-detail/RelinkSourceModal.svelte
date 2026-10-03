<script lang="ts">
    import { Image as ImageIcon, Link2, LoaderCircle, Search, X } from "$shared/ui/Icons.svelte";
    import { errorMessage, relinkMedia, searchExternal } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import { sourceBadgeClasses } from "$entities/media/model/mediaLabels";
    import type { ExternalMedia, MediaType, SearchScope } from "$shared/types";

    /** Anime is its own search bucket; anything the aggregator does not know becomes "all". */
    const SEARCHABLE = new Set<string>([
        "anime",
        "manga",
        "movie",
        "tvshow",
        "game",
        "book",
    ]);

    interface Props {
        isOpen: boolean;
        mediaId: string;
        /** The library item being re-pointed: supplies the search term and the type filter. */
        title: string;
        type: MediaType | string;
        currentSource?: string | null;
        onClose: () => void;
        /** Receives the refreshed detail payload so the screen can drop it in place. */
        onRelinked: (payload: Awaited<ReturnType<typeof relinkMedia>>) => void;
    }

    let {
        isOpen,
        mediaId,
        title,
        type,
        currentSource = null,
        onClose,
        onRelinked,
    }: Props = $props();

    /** Anime is its own search bucket; anything the aggregator does not know becomes "all". */
    const scope = $derived<SearchScope>(
        SEARCHABLE.has(type) ? (type as SearchScope) : "all",
    );

    let query = $state("");
    let results = $state<ExternalMedia[]>([]);
    let searching = $state(false);
    let searchError = $state<unknown>(null);
    let linkingId = $state("");
    let linkError = $state<unknown>(null);
    let input = $state<HTMLInputElement | null>(null);
    let controller: AbortController | null = null;
    let sequence = 0;

    const term = $derived(query.trim());
    const canSearch = $derived(term.length >= 2);

    // Prefilled with the current title, so the common case is a single press of Enter.
    $effect(() => {
        if (isOpen && !query) {
            query = title;
            requestAnimationFrame(() => input?.focus());
        }
    });

    // Debounced the same way the search modal is: one request per pause in typing, and an
    // out-of-order answer never overwrites a newer one.
    $effect(() => {
        const current = term;
        if (!isOpen || current.length < 2) {
            results = [];
            searching = false;
            return;
        }

        const mine = ++sequence;
        controller?.abort();
        const local = new AbortController();
        controller = local;
        searching = true;
        searchError = null;

        const timer = setTimeout(() => {
            void searchExternal(scope, current, local.signal)
                .then((rows) => {
                    if (mine === sequence) results = rows;
                })
                .catch((error) => {
                    if (mine === sequence && !(error instanceof DOMException)) {
                        searchError = error;
                        results = [];
                    }
                })
                .finally(() => {
                    if (mine === sequence) searching = false;
                });
        }, 500);

        return () => {
            clearTimeout(timer);
            local.abort();
        };
    });

    async function link(result: ExternalMedia) {
        if (linkingId) return;
        linkingId = result.externalId;
        linkError = null;
        try {
            const payload = await relinkMedia(mediaId, {
                externalId: result.externalId,
                source: result.externalSource ?? "",
                type,
            });
            onRelinked(payload);
        } catch (error) {
            linkError = error;
        } finally {
            linkingId = "";
        }
    }
</script>
<Modal {isOpen} {onClose} size="lg" labelledBy="relink-title">
    <div class="flex max-h-[70vh] flex-col">
        <header class="flex items-center gap-3 border-b border-white/[0.08] px-5 py-4">
            <Link2
                size={18}
                class="shrink-0 text-[var(--color-accent-soft)]"
                aria-hidden="true"
            />
            <div class="min-w-0">
                <h2 id="relink-title" class="text-sm font-bold text-white">
                    {i18n.current === "ru" ? "Сменить источник" : "Change source"}
                </h2>
                <p class="truncate text-xs text-muted">
                    {i18n.current === "ru"
                        ? "Найдите тот же тайтл в другом провайдере и привяжите его к этой записи."
                        : "Find the same title in another provider and attach it to this record."}
                </p>
            </div>
            <button
                type="button"
                class="ml-auto shrink-0 rounded-md p-1.5 text-muted transition hover:bg-white/5 hover:text-white"
                aria-label={i18n.current === "ru" ? "Закрыть" : "Close"}
                onclick={onClose}
            >
                <X size={16} aria-hidden="true" />
            </button>
        </header>

        <div class="border-b border-white/[0.08] p-4">
            <div
                class="flex h-10 items-center gap-2 rounded-lg border border-white/[0.08] bg-[#1c202b] px-3"
            >
                <Search size={15} class="shrink-0 text-muted" aria-hidden="true" />
                <input
                    bind:this={input}
                    bind:value={query}
                    type="search"
                    placeholder={i18n.current === "ru"
                        ? "Название тайтла…"
                        : "Title name…"}
                    aria-label={i18n.current === "ru"
                        ? "Поиск тайтла"
                        : "Search title"}
                    class="w-full bg-transparent text-sm text-white outline-none placeholder:text-muted"
                />
                {#if searching}
                    <LoaderCircle
                        size={15}
                        class="shrink-0 animate-spin text-[var(--color-accent-soft)]"
                        aria-hidden="true"
                    />
                {/if}
            </div>
            {#if currentSource}
                <p class="mt-2 text-xs text-muted">
                    {i18n.current === "ru"
                        ? "Текущий источник"
                        : "Current source"}: <span class="text-slate-300"
                        >{currentSource}</span
                    >
                </p>
            {/if}
        </div>
<div class="thin-scroll min-h-40 flex-1 overflow-y-auto p-4">
            {#if searchError}
                <p class="text-sm text-rose-200" role="alert">
                    {errorMessage(searchError)}
                </p>
            {:else if !canSearch}
                <p class="px-1 py-6 text-center text-sm text-muted">
                    {i18n.current === "ru"
                        ? "Введите хотя бы 2 символа."
                        : "Type at least 2 characters."}
                </p>
            {:else if !searching && results.length === 0}
                <p class="px-1 py-6 text-center text-sm text-muted">
                    {i18n.current === "ru"
                        ? "Ничего не найдено. Попробуйте другое название."
                        : "Nothing found. Try another title."}
                </p>
            {:else}
                <ul class="space-y-2">
                    {#each results as result (result.externalId)}
                        <li
                            class="flex items-center gap-3 rounded-lg border border-white/[0.06] bg-[var(--color-panel-line)] p-2.5"
                        >
                            <div
                                class="aspect-[2/3] h-14 w-10 shrink-0 overflow-hidden rounded-md bg-[var(--color-field)]"
                            >
                                {#if result.coverUrl}
                                    <img
                                        src={result.coverUrl}
                                        alt={result.title}
                                        class="h-full w-full object-cover"
                                        loading="lazy"
                                    />
                                {:else}
                                    <div class="grid h-full place-items-center text-muted">
                                        <ImageIcon size={16} aria-hidden="true" />
                                    </div>
                                {/if}
                            </div>

                            <div class="min-w-0 flex-1">
                                <p class="truncate text-sm font-semibold text-white">
                                    {result.title}
                                </p>
                                <div class="mt-1 flex flex-wrap items-center gap-1.5">
                                    {#if result.externalSource}
                                        <span
                                            class={`rounded border px-1.5 py-0.5 text-[10px] font-semibold ${sourceBadgeClasses(result.externalSource)}`}
                                        >
                                            {result.externalSource}
                                        </span>
                                    {/if}
                                    {#if result.releaseYear}
                                        <span class="text-[11px] text-muted">
                                            {result.releaseYear}
                                        </span>
                                    {/if}
                                </div>
                            </div>

                            <button
                                type="button"
                                class="shrink-0 rounded-md border border-[var(--color-accent)]/40 bg-[var(--color-accent)]/10 px-3 py-1.5 text-xs font-semibold text-[var(--color-accent-soft)] transition hover:bg-[var(--color-accent)]/20 disabled:cursor-wait disabled:opacity-50"
                                disabled={Boolean(linkingId)}
                                onclick={() => void link(result)}
                            >
                                {#if linkingId === result.externalId}
                                    <LoaderCircle
                                        size={13}
                                        class="animate-spin"
                                        aria-hidden="true"
                                    />
                                {:else}
                                    {i18n.current === "ru" ? "Привязать" : "Link"}
                                {/if}
                            </button>
                        </li>
                    {/each}
                </ul>
            {/if}
        </div>

        {#if linkError}
            <p
                class="border-t border-white/[0.08] px-5 py-3 text-xs text-rose-300"
                role="alert"
            >
                {errorMessage(linkError)}
            </p>
        {/if}
    </div>
</Modal>