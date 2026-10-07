<script lang="ts">
    import { Bookmark, Flame, Heart, List, Pencil, Plus, Sparkles, Star, Trash2, Layers } from "$shared/ui/Icons.svelte";
    import { deleteList, errorMessage, getListDetail, getLists, removeMediaFromList } from "$shared/api/api";
    import { fullSizeCoverUrl } from "$entities/media/model/coverUrl";
    import CreateListModal from "$features/lists/CreateListModal.svelte";
    import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import { showToast } from "$shared/ui/toast.svelte";
    import type { CustomListDetail, CustomListSummary, MediaItem } from "$shared/types";
    import ImportModal from "$features/import-media/ImportModal.svelte";

    interface Props { onOpen: (item: MediaItem) => void; onImportCompleted: () => void; }
    let { onOpen, onImportCompleted }: Props = $props();

    let lists = $state<CustomListSummary[]>([]);
    let selected = $state<CustomListDetail | null>(null);
    let loading = $state(true);
    let error = $state("");
    let modalOpen = $state(false);
    let importOpen = $state(false);
    let editing = $state<CustomListSummary | null>(null);
    const iconComponents = { list: List, bookmark: Bookmark, heart: Heart, star: Star, sparkles: Sparkles, flame: Flame } as const;
    const SelectedIcon = $derived(iconComponents[selected?.icon as keyof typeof iconComponents] ?? List);

    async function loadLists() {
        loading = true;
        error = "";
        try {
            lists = await getLists();
            const listId = selected?.id ?? new URLSearchParams(window.location.search).get("listId");
            if (listId) selected = await getListDetail(listId).catch(() => null);
        } catch (caught) {
            error = errorMessage(caught);
        } finally {
            loading = false;
        }
    }

    async function openList(list: CustomListSummary) {
        loading = true;
        error = "";
        try {
            selected = await getListDetail(list.id);
            const url = new URL(window.location.href);
            url.searchParams.set("listId", list.id);
            window.history.replaceState(null, "", url);
        }
        catch (caught) { error = errorMessage(caught); }
        finally { loading = false; }
    }

    function openCreate(list: CustomListSummary | null = null) {
        editing = list;
        modalOpen = true;
    }

    function closeList() {
        selected = null;
        const url = new URL(window.location.href);
        url.searchParams.delete("listId");
        window.history.replaceState(null, "", url);
    }

    async function removeList(list: CustomListSummary) {
        if (!window.confirm(i18n.t.views.listConfirmDelete(list.name))) return;
        try {
            await deleteList(list.id);
            if (selected?.id === list.id) selected = null;
            showToast(i18n.t.views.listDeleted);
            await loadLists();
        } catch (caught) { showToast(errorMessage(caught), "error"); }
    }

    async function removeItem(item: MediaItem) {
        if (!selected) return;
        const active = selected;
        selected = { ...active, items: active.items.filter((value) => value.id !== item.id) };
        try {
            await removeMediaFromList(active.id, item.id);
            showToast(i18n.t.views.listRemoved(active.name));
            await loadLists();
        } catch (caught) {
            showToast(errorMessage(caught), "error");
            selected = await getListDetail(active.id).catch(() => null);
        }
    }

    function updatedDate(value: string) {
        return new Intl.DateTimeFormat(i18n.current, { day: "numeric", month: "short", year: "numeric" }).format(new Date(value));
    }

    async function showImportedList(id: string) {
        await loadLists();
        selected = await getListDetail(id).catch(() => null);
        if (selected) { const url = new URL(window.location.href); url.searchParams.set("listId", id); window.history.replaceState(null, "", url); }
    }

    $effect(() => { void loadLists(); });
</script>

<div class="space-y-6 w-full">
    {#if selected}
        <div class="flex flex-wrap items-start justify-between gap-4">
            <div class="min-w-0">
                <button type="button" class="mb-4 inline-flex items-center gap-2 text-sm text-muted hover:text-white" onclick={closeList}>
                    <span aria-hidden="true">←</span>{i18n.t.views.listBack}
                </button>
                <div class="flex items-center gap-3">
                    <span class="grid h-12 w-12 shrink-0 place-items-center rounded-xl text-white" style={`background:${selected.color ?? "#5844e0"}`}>
                        <SelectedIcon size={23}></SelectedIcon>
                    </span>
                    <div class="min-w-0"><h2 class="truncate text-2xl font-bold text-ink">{selected.name}</h2><p class="mt-1 text-sm text-muted">{i18n.t.views.listTitles(selected.items.length)}</p></div>
                </div>
                {#if selected.description}<p class="mt-4 max-w-2xl text-sm leading-6 text-muted">{selected.description}</p>{/if}
            </div>
            <div class="flex gap-2 pt-10">
                <button type="button" class="inline-flex items-center gap-2 rounded-lg border border-white/10 bg-card px-3 py-2 text-sm text-ink hover:bg-card-hover" onclick={() => openCreate(lists.find((list) => list.id === selected?.id) ?? null)}><Pencil size={15} />{i18n.t.views.listEdit}</button>
                <button type="button" class="inline-flex items-center gap-2 rounded-lg border border-rose-400/20 bg-rose-400/5 px-3 py-2 text-sm text-rose-300 hover:bg-rose-400/10" onclick={() => { const list = lists.find((value) => value.id === selected?.id); if (list) void removeList(list); }}><Trash2 size={15} />{i18n.t.views.listDelete}</button>
            </div>
        </div>
        <MediaGrid items={selected.items} showProgress={false} loading={loading} error={error || null} onRetry={() => { const list = lists.find((value) => value.id === selected?.id); if (list) void openList(list); }} onOpen={onOpen} onRemoveFromList={removeItem} />
    {:else}
        <div class="flex flex-wrap items-end justify-between gap-4">
            <div><p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p><h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">{i18n.t.views.listsTitle}</h2></div>
            <div class="flex gap-2"><button type="button" class="inline-flex items-center gap-2 rounded-lg border border-white/10 bg-card px-4 py-2 text-sm font-semibold text-ink hover:bg-card-hover" onclick={() => (importOpen = true)}><Layers size={16} />{i18n.t.importModal.start}</button>{#if lists.length > 0}<button type="button" class="tap inline-flex items-center gap-2 rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white hover:bg-accent-hover" onclick={() => openCreate()}><Plus size={16} />{i18n.t.views.listsCreate}</button>{/if}</div>
        </div>
        {#if loading}
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">{#each [1,2,3] as item (item)}<div class="h-56 animate-pulse rounded-xl border border-white/[0.06] bg-card"></div>{/each}</div>
        {:else if error}
            <div class="rounded-xl border border-rose-400/20 bg-rose-400/5 p-6 text-center text-sm text-rose-200" role="alert">{error}<button class="ml-3 underline" onclick={() => void loadLists()}>{i18n.t.common.retry}</button></div>
        {:else if lists.length === 0}
            <div class="flex flex-col items-center rounded-2xl border border-dashed border-white/10 bg-card px-5 py-14 text-center">
                <div class="grid h-16 w-16 place-items-center rounded-2xl border border-white/10 bg-elevated text-accent-soft"><Sparkles size={27} /></div>
                <h3 class="mt-5 text-lg font-semibold text-ink">{i18n.t.views.listsEmptyTitle}</h3><p class="mt-2 max-w-md text-sm leading-6 text-muted">{i18n.t.views.listsEmptyHint}</p>
                <button type="button" class="mt-6 inline-flex items-center gap-2 rounded-lg bg-accent px-4 py-2.5 text-sm font-semibold text-white hover:bg-accent-hover" onclick={() => openCreate()}><Plus size={16} />{i18n.t.views.listCreateFirst}</button>
            </div>
        {:else}
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {#each lists as list (list.id)}
                    <article class="group overflow-hidden rounded-xl border border-white/[0.07] bg-card transition hover:border-white/15 hover:bg-card-hover">
                        <button type="button" class="block w-full text-left" onclick={() => void openList(list)}>
                            <div class="relative h-44 w-full overflow-hidden rounded-t-xl bg-card">
                                {#if list.previewCovers.length === 0}
                                    {@const Icon = iconComponents[list.icon as keyof typeof iconComponents] ?? List}
                                    <div class="flex h-full w-full items-center justify-center" style={`background:linear-gradient(135deg, ${list.color ?? "#5844e0"}44, transparent)`}><span class="grid h-16 w-16 place-items-center rounded-2xl border border-white/10 text-white shadow-lg" style={`background:${list.color ?? "#5844e0"}`}><Icon size={27} /></span></div>
                                {:else if list.previewCovers.length === 1}
                                    {@const cover = list.previewCovers[0]}
                                    <div class="flex h-full w-full items-center justify-center">
                                        {#if cover}
                                            <img src={fullSizeCoverUrl(cover)} alt="" loading="lazy" class="pointer-events-none absolute inset-0 h-full w-full scale-125 object-cover opacity-25 blur-[20px]" />
                                            <img src={fullSizeCoverUrl(cover)} alt="" loading="lazy" class="z-10 aspect-[2/3] h-36 rounded-lg object-cover shadow-2xl shadow-black/90 ring-1 ring-white/10" />
                                        {:else}
                                            <div class="z-10 aspect-[2/3] h-36 rounded-lg shadow-2xl shadow-black/90 ring-1 ring-white/10" style={`background:${list.color ?? "#5844e0"}`}></div>
                                        {/if}
                                    </div>
                                {:else}
                                    <div class="flex h-full w-full items-center justify-center -space-x-5 px-4">
                                        {#each list.previewCovers as cover, index (`${index}-${cover}`)}
                                            {#if cover}
                                                <img src={fullSizeCoverUrl(cover)} alt="" loading="lazy" class="aspect-[2/3] h-32 shrink-0 rounded-lg object-cover shadow-xl shadow-black/80 ring-1 ring-white/10 transition-transform hover:scale-105 hover:z-20 sm:h-36" />
                                            {:else}
                                                <div class="aspect-[2/3] h-32 shrink-0 rounded-lg shadow-xl shadow-black/80 ring-1 ring-white/10 transition-transform hover:scale-105 hover:z-20 sm:h-36" style={`background:${list.color ?? "#5844e0"}`}></div>
                                            {/if}
                                        {/each}
                                    </div>
                                {/if}
                                <span class="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/70 to-transparent"></span>
                            </div>
                            <div class="p-4 pb-2"><h3 class="truncate text-base font-semibold text-ink">{list.name}</h3><p class="mt-1 line-clamp-2 min-h-10 text-sm leading-5 text-muted">{list.description || " "}</p></div>
                        </button>
                        <div class="flex items-center justify-between gap-2 px-4 pb-4 text-xs text-muted"><span>{i18n.t.views.listTitles(list.itemsCount)}</span><span>{i18n.t.views.listUpdated} · {updatedDate(list.updatedAt)}</span>
                            <span class="flex gap-1 opacity-100 transition sm:opacity-0 sm:group-hover:opacity-100">
                                <button type="button" title={i18n.t.views.listEdit} aria-label={i18n.t.views.listEdit} class="grid h-8 w-8 place-items-center rounded-md hover:bg-white/10 hover:text-white" onclick={() => openCreate(list)}><Pencil size={15} /></button>
                                <button type="button" title={i18n.t.views.listDelete} aria-label={i18n.t.views.listDelete} class="grid h-8 w-8 place-items-center rounded-md hover:bg-rose-400/10 hover:text-rose-300" onclick={() => void removeList(list)}><Trash2 size={15} /></button>
                            </span>
                        </div>
                    </article>
                {/each}
            </div>
        {/if}
    {/if}
</div>
<ImportModal isOpen={importOpen} onClose={() => (importOpen = false)} onImportCompleted={() => { onImportCompleted(); void loadLists(); }} onNavigateToList={showImportedList} />

<CreateListModal isOpen={modalOpen} list={editing} onClose={() => (modalOpen = false)} onSaved={() => void loadLists()} />
