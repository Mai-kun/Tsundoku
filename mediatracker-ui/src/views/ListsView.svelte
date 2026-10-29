<script lang="ts">
  import {
    Bookmark,
    Flame,
    Heart,
    List,
    Pencil,
    Plus,
    Sparkles,
    Star,
    Trash2,
    Layers,
  } from "$shared/ui/Icons";
  import {
    deleteList,
    errorMessage,
    getListDetail,
    getLists,
    removeMediaFromList,
  } from "$shared/api/api";
  import { fullSizeCoverUrl } from "$entities/media/model/coverUrl";
  import MediaCoverPlaceholder from "$shared/ui/MediaCoverPlaceholder.svelte";
  import CreateListModal from "$features/lists/CreateListModal.svelte";
  import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import type { CustomListDetail, CustomListSummary, MediaItem } from "$shared/types";
  import ImportModal from "$features/import-media/ImportModal.svelte";

  interface Props {
    onOpen: (item: MediaItem) => void;
    onImportCompleted: () => void;
  }
  let { onOpen, onImportCompleted }: Props = $props();

  let lists = $state.raw<CustomListSummary[]>([]);
  let selected = $state<CustomListDetail | null>(null);
  let loading = $state(true);
  let error = $state("");
  let modalOpen = $state(false);
  let importOpen = $state(false);
  let editing = $state<CustomListSummary | null>(null);
  let brokenCovers = $state<Set<string>>(new Set());

  // Svelte 5 does not re-render on Set#add mutation, so reassign the set to trigger reactivity.
  function markBroken(url: string) {
    brokenCovers = new Set(brokenCovers).add(url);
  }
  const iconComponents = {
    list: List,
    bookmark: Bookmark,
    heart: Heart,
    star: Star,
    sparkles: Sparkles,
    flame: Flame,
  } as const;
  const SelectedIcon = $derived(
    iconComponents[selected?.icon as keyof typeof iconComponents] ?? List,
  );

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
      url.searchParams.set("view", "lists");
      url.searchParams.set("listId", list.id);
      window.history.pushState({ listId: list.id }, "", url);
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      loading = false;
    }
  }

  function openCreate(list: CustomListSummary | null = null) {
    editing = list;
    modalOpen = true;
  }

  function closeList() {
    selected = null;
    const url = new URL(window.location.href);
    url.searchParams.delete("listId");
    // Pushing an entry on "Back" creates duplicate stack entries and traps the user, so go back
    // when we arrived via a pushed list state, otherwise replace the URL without adding forward
    // history.
    if (window.history.state?.listId) {
      window.history.back();
    } else {
      window.history.replaceState(null, "", url);
    }
  }

  async function removeList(list: CustomListSummary) {
    if (!window.confirm(i18n.t.views.listConfirmDelete(list.name))) return;
    try {
      await deleteList(list.id);
      if (selected?.id === list.id) selected = null;
      showToast(i18n.t.views.listDeleted);
      await loadLists();
    } catch (caught) {
      showToast(errorMessage(caught), "error");
    }
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
    return new Intl.DateTimeFormat(i18n.current, {
      day: "numeric",
      month: "short",
      year: "numeric",
    }).format(new Date(value));
  }

  async function showImportedList(id: string) {
    await loadLists();
    selected = await getListDetail(id).catch(() => null);
    if (selected) {
      const url = new URL(window.location.href);
      url.searchParams.set("listId", id);
      window.history.replaceState(null, "", url);
    }
  }

  $effect(() => {
    void loadLists();

    const onPopState = () => {
      const params = new URLSearchParams(window.location.search);
      const listId = params.get("listId");
      if (!listId && selected) {
        selected = null;
      } else if (listId && (!selected || selected.id !== listId)) {
        const found = lists.find((l) => l.id === listId);
        if (found) void openList(found);
      }
    };
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  });
</script>

<div class="w-full space-y-6">
  {#if selected}
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0">
        <button
          type="button"
          class="text-muted mb-4 inline-flex items-center gap-2 text-sm hover:text-white"
          onclick={closeList}
        >
          <span aria-hidden="true">←</span>{i18n.t.views.listBack}
        </button>
        <div class="flex items-center gap-3">
          <span
            class="grid h-12 w-12 shrink-0 place-items-center rounded-xl text-white"
            style={`background:${selected.color ?? "#5844e0"}`}
          >
            <SelectedIcon size={23}></SelectedIcon>
          </span>
          <div class="min-w-0">
            <h2 class="text-ink truncate text-2xl font-bold">{selected.name}</h2>
            <p class="text-muted mt-1 text-sm">{i18n.t.views.listTitles(selected.items.length)}</p>
          </div>
        </div>
        {#if selected.description}<p class="text-muted mt-4 max-w-2xl text-sm leading-6">
            {selected.description}
          </p>{/if}
      </div>
      <div class="flex gap-2 pt-10">
        <button
          type="button"
          class="bg-card text-ink hover:bg-card-hover inline-flex items-center gap-2 rounded-lg border border-white/10 px-3 py-2 text-sm"
          onclick={() => openCreate(lists.find((list) => list.id === selected?.id) ?? null)}
          ><Pencil size={15} />{i18n.t.views.listEdit}</button
        >
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg border border-rose-400/20 bg-rose-400/5 px-3 py-2 text-sm text-rose-300 hover:bg-rose-400/10"
          onclick={() => {
            const list = lists.find((value) => value.id === selected?.id);
            if (list) void removeList(list);
          }}><Trash2 size={15} />{i18n.t.views.listDelete}</button
        >
      </div>
    </div>
    {#if selected.isSmart && selected.smartQueryJson}
      {@const sq = (() => {
        try {
          return JSON.parse(selected.smartQueryJson!);
        } catch {
          return null;
        }
      })()}
      {#if sq}
        <div
          class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-violet-400/20 bg-violet-400/5 px-4 py-2.5 text-xs text-violet-300"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-semibold">⚡ {i18n.t.views.smartBadge}</span>
            {#if sq.categories?.length}<span class="rounded-full bg-violet-400/15 px-2 py-0.5"
                >{sq.categories.join(" · ")}</span
              >{/if}
            {#if sq.statuses?.length}<span class="rounded-full bg-violet-400/15 px-2 py-0.5"
                >{sq.statuses
                  .map(
                    (s: number) =>
                      ["В планах", "В процессе", "Завершено", "На паузе", "Брошено"][s],
                  )
                  .join(" · ")}</span
              >{/if}
            {#if sq.maxEpisodes}<span class="rounded-full bg-violet-400/15 px-2 py-0.5"
                >≤{sq.maxEpisodes} эп.</span
              >{/if}
            {#if sq.maxDurationMinutes}<span class="rounded-full bg-violet-400/15 px-2 py-0.5"
                >≤{sq.maxDurationMinutes} мин</span
              >{/if}
            {#if sq.maxPages}<span class="rounded-full bg-violet-400/15 px-2 py-0.5"
                >≤{sq.maxPages} стр.</span
              >{/if}
            {#if sq.minScore}<span class="rounded-full bg-violet-400/15 px-2 py-0.5"
                >★{sq.minScore}+</span
              >{/if}
          </div>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 rounded-lg border border-violet-400/30 bg-violet-400/10 px-2.5 py-1 text-xs font-medium text-violet-200 hover:bg-violet-400/20"
            onclick={() => openCreate(lists.find((list) => list.id === selected?.id) ?? null)}
          >
            <Pencil size={12} />
            {i18n.t.views.smartEditRules}
          </button>
        </div>
      {/if}
    {/if}
    <MediaGrid
      items={selected.items}
      showProgress={false}
      {loading}
      error={error || null}
      onRetry={() => {
        const list = lists.find((value) => value.id === selected?.id);
        if (list) void openList(list);
      }}
      {onOpen}
      onRemoveFromList={selected.isSmart ? undefined : removeItem}
    />
  {:else}
    <div class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p class="text-accent-soft text-xs font-semibold tracking-[0.18em] uppercase">
          {i18n.t.library.collectionLabel}
        </p>
        <h2 class="text-ink mt-1 text-2xl font-bold tracking-tight">{i18n.t.views.listsTitle}</h2>
      </div>
      <div class="flex gap-2">
        <button
          type="button"
          class="bg-card text-ink hover:bg-card-hover inline-flex items-center gap-2 rounded-lg border border-white/10 px-4 py-2 text-sm font-semibold"
          onclick={() => (importOpen = true)}><Layers size={16} />{i18n.t.importModal.start}</button
        >{#if lists.length > 0}<button
            type="button"
            class="tap bg-accent hover:bg-accent-hover inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-white"
            onclick={() => openCreate()}><Plus size={16} />{i18n.t.views.listsCreate}</button
          >{/if}
      </div>
    </div>
    {#if loading}
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {#each [1, 2, 3] as item (item)}<div
            class="bg-card h-56 animate-pulse rounded-xl border border-white/[0.06]"
          ></div>{/each}
      </div>
    {:else if error}
      <div
        class="rounded-xl border border-rose-400/20 bg-rose-400/5 p-6 text-center text-sm text-rose-200"
        role="alert"
      >
        {error}<button type="button" class="ml-3 underline" onclick={() => void loadLists()}
          >{i18n.t.common.retry}</button
        >
      </div>
    {:else if lists.length === 0}
      <div
        class="bg-card flex flex-col items-center rounded-2xl border border-dashed border-white/10 px-5 py-14 text-center"
      >
        <div
          class="bg-elevated text-accent-soft grid h-16 w-16 place-items-center rounded-2xl border border-white/10"
        >
          <Sparkles size={27} />
        </div>
        <h3 class="text-ink mt-5 text-lg font-semibold">{i18n.t.views.listsEmptyTitle}</h3>
        <p class="text-muted mt-2 max-w-md text-sm leading-6">{i18n.t.views.listsEmptyHint}</p>
        <button
          type="button"
          class="bg-accent hover:bg-accent-hover mt-6 inline-flex items-center gap-2 rounded-lg px-4 py-2.5 text-sm font-semibold text-white"
          onclick={() => openCreate()}><Plus size={16} />{i18n.t.views.listCreateFirst}</button
        >
      </div>
    {:else}
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {#each lists as list (list.id)}
          <article
            class="group bg-card hover:bg-card-hover overflow-hidden rounded-xl border border-white/[0.07] transition hover:border-white/15"
          >
            <button
              type="button"
              class="block w-full text-left"
              onclick={() => void openList(list)}
            >
              <div class="bg-card relative h-44 w-full overflow-hidden rounded-t-xl">
                {#if list.previewCovers.length === 0}
                  {@const Icon = iconComponents[list.icon as keyof typeof iconComponents] ?? List}
                  <div
                    class="flex h-full w-full items-center justify-center"
                    style={`background:linear-gradient(135deg, ${list.color ?? "#5844e0"}44, transparent)`}
                  >
                    <span
                      class="grid h-16 w-16 place-items-center rounded-2xl border border-white/10 text-white shadow-lg"
                      style={`background:${list.color ?? "#5844e0"}`}><Icon size={27} /></span
                    >
                  </div>
                {:else if list.previewCovers.length === 1}
                  {@const cover = list.previewCovers[0]}
                  <div class="flex h-full w-full items-center justify-center">
                    {#if cover && !brokenCovers.has(cover)}
                      <img
                        src={fullSizeCoverUrl(cover)}
                        alt=""
                        loading="lazy"
                        class="pointer-events-none absolute inset-0 h-full w-full scale-125 object-cover opacity-25 blur-[20px]"
                      />
                      <img
                        src={fullSizeCoverUrl(cover)}
                        alt=""
                        loading="lazy"
                        class="z-10 aspect-[2/3] h-36 rounded-lg object-cover shadow-2xl ring-1 shadow-black/90 ring-white/10"
                        onerror={(e) => {
                          const target = e.currentTarget as HTMLImageElement;
                          markBroken(cover);
                          target.src = "";
                        }}
                      />
                    {:else if cover}
                      <MediaCoverPlaceholder
                        class="z-10 aspect-[2/3] h-36 rounded-lg shadow-2xl ring-1 shadow-black/90 ring-white/10"
                      />
                    {:else}
                      <MediaCoverPlaceholder
                        class="z-10 aspect-[2/3] h-36 rounded-lg shadow-2xl ring-1 shadow-black/90 ring-white/10"
                      />
                    {/if}
                  </div>
                {:else}
                  <div class="flex h-full w-full items-center justify-center -space-x-5 px-4">
                    {#each list.previewCovers as cover, index (`${index}-${cover}`)}
                      {#if cover && !brokenCovers.has(cover)}
                        <img
                          src={fullSizeCoverUrl(cover)}
                          alt=""
                          loading="lazy"
                          class="aspect-[2/3] h-32 shrink-0 rounded-lg object-cover shadow-xl ring-1 shadow-black/80 ring-white/10 transition-transform hover:z-20 hover:scale-105 sm:h-36"
                          onerror={(e) => {
                            const target = e.currentTarget as HTMLImageElement;
                            markBroken(cover);
                            target.src = "";
                          }}
                        />
                      {:else if cover}
                        <MediaCoverPlaceholder
                          class="aspect-[2/3] h-32 shrink-0 rounded-lg shadow-xl ring-1 shadow-black/80 ring-white/10 transition-transform hover:z-20 hover:scale-105 sm:h-36"
                        />
                      {:else}
                        <MediaCoverPlaceholder
                          class="aspect-[2/3] h-32 shrink-0 rounded-lg shadow-xl ring-1 shadow-black/80 ring-white/10 transition-transform hover:z-20 hover:scale-105 sm:h-36"
                        />
                      {/if}
                    {/each}
                  </div>
                {/if}
                <span
                  class="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/70 to-transparent"
                ></span>
                {#if list.isSmart}
                  <span
                    class="absolute top-2 right-2 z-20 inline-flex items-center gap-1 rounded-full border border-violet-400/40 bg-gradient-to-r from-violet-600/90 to-amber-600/90 px-2 py-0.5 text-[10px] font-semibold text-white shadow-lg backdrop-blur-sm"
                  >
                    ⚡ {i18n.t.views.smartBadge}
                  </span>
                {/if}
              </div>
              <div class="p-4 pb-2">
                <h3 class="text-ink truncate text-base font-semibold">{list.name}</h3>
                <p class="text-muted mt-1 line-clamp-2 min-h-10 text-sm leading-5">
                  {list.description || " "}
                </p>
                {#if list.isSmart && list.smartQueryJson}
                  {@const sq = (() => {
                    try {
                      return JSON.parse(list.smartQueryJson!);
                    } catch {
                      return null;
                    }
                  })()}
                  {#if sq}
                    <div class="mt-2 flex flex-wrap gap-1">
                      {#if sq.categories?.length}
                        <span
                          class="rounded bg-violet-400/10 px-1.5 py-0.5 text-[10px] font-medium text-violet-300"
                          >{sq.categories.join(", ")}</span
                        >
                      {/if}
                      {#if sq.minScore}
                        <span
                          class="rounded bg-amber-400/10 px-1.5 py-0.5 text-[10px] font-medium text-amber-300"
                          >★{sq.minScore}+</span
                        >
                      {/if}
                      {#if sq.maxEpisodes}
                        <span
                          class="text-muted rounded bg-white/10 px-1.5 py-0.5 text-[10px] font-medium"
                          >≤{sq.maxEpisodes} эп.</span
                        >
                      {/if}
                      {#if sq.maxDurationMinutes}
                        <span
                          class="text-muted rounded bg-white/10 px-1.5 py-0.5 text-[10px] font-medium"
                          >≤{sq.maxDurationMinutes}м</span
                        >
                      {/if}
                    </div>
                  {/if}
                {/if}
              </div>
            </button>
            <div class="text-muted flex items-center justify-between gap-2 px-4 pb-4 text-xs">
              <span>{i18n.t.views.listTitles(list.itemsCount)}</span><span
                >{i18n.t.views.listUpdated} · {updatedDate(list.updatedAt)}</span
              >
              <span
                class="flex gap-1 opacity-100 transition sm:opacity-0 sm:group-hover:opacity-100"
              >
                <button
                  type="button"
                  title={i18n.t.views.listEdit}
                  aria-label={i18n.t.views.listEdit}
                  class="grid h-8 w-8 place-items-center rounded-md hover:bg-white/10 hover:text-white"
                  onclick={() => openCreate(list)}><Pencil size={15} /></button
                >
                <button
                  type="button"
                  title={i18n.t.views.listDelete}
                  aria-label={i18n.t.views.listDelete}
                  class="grid h-8 w-8 place-items-center rounded-md hover:bg-rose-400/10 hover:text-rose-300"
                  onclick={() => void removeList(list)}><Trash2 size={15} /></button
                >
              </span>
            </div>
          </article>
        {/each}
      </div>
    {/if}
  {/if}
</div>
<ImportModal
  isOpen={importOpen}
  onClose={() => (importOpen = false)}
  onImportCompleted={() => {
    onImportCompleted();
    void loadLists();
  }}
  onNavigateToList={showImportedList}
/>

<CreateListModal
  isOpen={modalOpen}
  list={editing}
  onClose={() => (modalOpen = false)}
  onSaved={() => void loadLists()}
/>
