<script lang="ts">
  import { deleteMedia } from "$shared/api/api";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import FirstRunStorageModal from "$features/settings/FirstRunStorageModal.svelte";
  import AppShell from "$widgets/layout/AppShell.svelte";
  import Header from "$widgets/layout/Header.svelte";
  import Sidebar from "$widgets/layout/Sidebar.svelte";
  import { dropPromptState } from "$features/drop-reason/dropReasonPrompt.svelte";
  import CategoryView from "$views/CategoryView.svelte";
  import type { Category } from "$views/categoryModel";
  import HomeView from "$views/HomeView.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import { bumpGridLayout } from "$widgets/media-grid/gridLayout.svelte";
  import type {
    AppView,
    JobProgress,
    MediaItem,
    SearchModalContext,
    SearchScope,
  } from "$shared/types";

  const categories: readonly Category[] = ["tvshow", "movie", "anime", "manga", "game", "book"];
  const views: readonly AppView[] = [
    "home",
    ...categories,
    "stats",
    "lists",
    "history",
    "calendar",
    "seasons",
    "detail",
  ];

  let route = readRoute();
  let activeView = $state<AppView>(route.view);
  /* What is actually in the DOM. The swap is a plain state write: Svelte 5 flushes it in a
       microtask, i.e. before the browser paints, so the outgoing {#if} branch is destroyed and
       the incoming one mounted within the same frame. flushSync() used to force that mid-task
       and blocked the main thread for hundreds of ms on every category switch; the microtask
       flush already guarantees the browser never paints two views stacked, or an empty <main>.

       There is deliberately no "hide the area until the swap settles" step: the settle check used
       to count <main>'s children, but MediaDetailView renders four top-level nodes (root + three
       modals), so the count never reached 1, `switching` stayed true and <main> kept `invisible`
       -- the detail page mounted and stayed invisible until F5. */
  let renderedView = $state<AppView | null>(route.view);
  let activeCategory = $state<Category | null>(isCategory(route.view) ? route.view : null);
  let previousView = $state<AppView>(
    route.view === "seasons" || route.view === "detail" ? "home" : route.view,
  );
  let selectedMediaId = $state<string | null>(route.mediaId);
  let isCreateOpen = $state(false);
  let editingItem = $state<MediaItem | null>(null);
  let isSearchOpen = $state(false);
  let isSettingsOpen = $state(false);
  let initialSearchType = $state<SearchScope>("all");
  let initialSearchQuery = $state("");
  let initialSearchSource = $state("");
  let initialSearchByCreator = $state(false);
  let mediaRevision = $state(0);
  let modalTrigger = $state<HTMLElement | null>(null);
  let detailDepth = 0;
  let mainScrollContainer = $state<HTMLElement | null>(null);
  const savedScrollPositions = new Map<string, number>();

  function setScroll(value: number) {
    if (mainScrollContainer) mainScrollContainer.scrollTop = value;
  }

  function restoreScroll(view: string) {
    if (view === "detail") return;
    const saved = savedScrollPositions.get(view);
    if (typeof saved === "number") {
      requestAnimationFrame(() => setScroll(saved));
    }
  }

  $effect(() => {
    const syncFromHistory = () => {
      // A modal is open: the Back/Forward button must only close the modal,
      // never navigate the background view or scroll it.
      if (isModalOpen()) {
        closeAllModals();
        return;
      }

      const nextRoute = readRoute();
      // Popping the modal state we pushed leaves the URL (and thus the route)
      // unchanged, so nothing actually navigated: don't scroll or swap views.
      if (nextRoute.view === activeView && nextRoute.mediaId === selectedMediaId) {
        return;
      }

      activeView = nextRoute.view;
      selectedMediaId = nextRoute.mediaId;
      switchView(nextRoute.view);
      if (nextRoute.view === "detail") {
        setScroll(0);
      } else {
        detailDepth = 0;
        restoreScroll(nextRoute.view);
        if (nextRoute.view === "home" && !savedScrollPositions.has("home")) {
          setScroll(0);
        }
      }
    };

    window.addEventListener("popstate", syncFromHistory);
    return () => window.removeEventListener("popstate", syncFromHistory);
  });

  function readRoute(): { view: AppView; mediaId: string | null } {
    if (typeof window === "undefined") {
      return { view: "home", mediaId: null };
    }

    const parameters = new URLSearchParams(window.location.search);
    const candidate = parameters.get("view");
    const saved = uiSettings.lastView as AppView;
    const view =
      candidate && views.includes(candidate as AppView)
        ? (candidate as AppView)
        : views.includes(saved)
          ? saved
          : "home";
    const requiresMedia = view === "seasons" || view === "detail";
    const mediaId = requiresMedia ? parameters.get("mediaId") : null;

    return mediaId || !requiresMedia ? { view, mediaId } : { view: "home", mediaId: null };
  }

  function writeRoute(view: AppView, mediaId: string | null) {
    const url = new URL(window.location.href);
    url.searchParams.set("view", view);

    if ((view === "seasons" || view === "detail") && mediaId) {
      url.searchParams.set("mediaId", mediaId);
    } else {
      url.searchParams.delete("mediaId");
    }

    if (view !== "detail" || previousView !== "lists") {
      url.searchParams.delete("listId");
    }

    window.history.pushState(null, "", url);
  }

  /**
   * Single entry point for changing views. The state write is flushed by Svelte in a
   * microtask, before the browser paints, so only the final state is ever on screen.
   */
  function switchView(view: AppView) {
    if (isCategory(view)) {
      activeCategory = view;
    }
    renderedView = view;
  }

  $effect(() => {
    if (renderedView === "home" || (renderedView !== null && isCategory(renderedView))) {
      requestAnimationFrame(() => bumpGridLayout());
    }
  });

  function navigate(view: AppView) {
    // Remember where the outgoing view was scrolled: the home reset below
    // (and any view swap) would otherwise lose it for history back.
    if (activeView !== view) {
      savedScrollPositions.set(activeView, mainScrollContainer?.scrollTop ?? 0);
    }
    activeView = view;
    selectedMediaId = null;
    detailDepth = 0;
    writeRoute(view, null);
    uiSettings.setLastView(view);
    // Home always opens from the top: the shared scroller would otherwise
    // keep the previous view's offset and clip the first rows.
    if (view === "home") setScroll(0);
    switchView(view);
  }

  /** Every caller (card click, related tile, search result) lands here; the state write is synchronous. */
  function openDetail(item: MediaItem) {
    if (activeView !== "detail") {
      previousView = activeView;
      savedScrollPositions.set(activeView, mainScrollContainer?.scrollTop ?? 0);
    }

    activeView = "detail";
    selectedMediaId = item.id;
    writeRoute("detail", item.id);
    detailDepth += 1;
    setScroll(0);
    switchView("detail");
  }

  function closeDetail() {
    savedScrollPositions.delete("detail");
    const target = previousView;
    if (detailDepth > 0) {
      detailDepth -= 1;
      window.history.back();
    } else {
      navigate(target);
    }
    restoreScroll(target);
  }

  async function deleteFromDetail(id: string) {
    await deleteMedia(id);
    mediaChanged();
  }

  function titleForView(view: AppView): string {
    switch (view) {
      case "home":
        return i18n.t.views.homeTitle;
      case "stats":
        return i18n.t.stats.title;
      case "lists":
        return i18n.t.views.listsTitle;
      case "history":
        return i18n.t.views.historyTitle;
      case "calendar":
        return i18n.t.views.calendarTitle;
      case "seasons":
        return i18n.t.navigation.seasons;
      case "detail":
        return i18n.t.detail.eyebrow;
      case "anime":
        return i18n.t.navigation.anime;
      default:
        return i18n.t.navigation[view];
    }
  }

  function isCategory(view: AppView): view is Category {
    return categories.includes(view as Category);
  }

  function searchTypeForView(view: AppView): SearchScope {
    return isCategory(view) ? view : "all";
  }

  function rememberTrigger() {
    modalTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  }

  function restoreModalFocus() {
    const trigger = modalTrigger;
    modalTrigger = null;
    requestAnimationFrame(() => trigger?.focus());
  }

  /** Pushes a modal entry onto the history stack so the Back button closes the
   *  modal instead of navigating the background screen. The URL is unchanged. */
  function pushModalState() {
    window.history.pushState({ modalOpen: true }, "");
  }

  /** Pops the modal entry pushed by pushModalState. Only call from a close
   *  path that already set its is*Open flag to false. */
  function popModalState() {
    if (window.history.state?.modalOpen) {
      window.history.back();
    }
  }

  function isModalOpen() {
    return (
      isSearchOpen ||
      isSettingsOpen ||
      isCreateOpen ||
      jobsClient.isModalOpen ||
      dropPromptState.target !== null
    );
  }

  /** Closes every app-level modal without touching the route or scroll. */
  function closeAllModals() {
    isSearchOpen = false;
    isSettingsOpen = false;
    isCreateOpen = false;
    editingItem = null;
    jobsClient.closeModal();
    dropPromptState.close();
    restoreModalFocus();
  }

  function openCreate() {
    rememberTrigger();
    editingItem = null;
    isCreateOpen = true;
    pushModalState();
  }

  function openEdit(item: MediaItem) {
    rememberTrigger();
    editingItem = item;
    isCreateOpen = true;
    pushModalState();
  }

  function closeCreate() {
    isCreateOpen = false;
    editingItem = null;
    popModalState();
    restoreModalFocus();
  }

  function openSearch(context: string | SearchModalContext = "") {
    rememberTrigger();
    if (typeof context === "string") {
      initialSearchType = "all";
      initialSearchQuery = context;
      initialSearchSource = "";
      initialSearchByCreator = false;
    } else {
      initialSearchType = (context.type as SearchScope) || "all";
      initialSearchQuery = context.query;
      initialSearchSource = context.source ?? "";
      initialSearchByCreator = Boolean(context.byCreator);
    }
    isSearchOpen = true;
    pushModalState();
  }

  function closeSearch() {
    isSearchOpen = false;
    popModalState();
    restoreModalFocus();
  }

  function openSettings() {
    rememberTrigger();
    isSettingsOpen = true;
    pushModalState();
  }

  function closeSettings() {
    isSettingsOpen = false;
    popModalState();
    restoreModalFocus();
  }

  function mediaChanged() {
    mediaRevision += 1;
  }

  function navigateToList(id: string) {
    navigate("lists");
    const url = new URL(window.location.href);
    url.searchParams.set("listId", id);
    window.history.pushState(null, "", url);
  }

  function handleCreated(_: MediaItem) {
    mediaChanged();
  }

  /* A finished background job rewrote the row behind the grid (cover, seasons, sync flag), so the
       lists have to be refetched — otherwise a card keeps its "Syncing" overlay forever. Failed and
       cancelled jobs also settle the row (it stays with syncStatus=failed), so they count too. The
       detail screen refreshes itself, but the signal still fires: HomeView and CategoryView live in
       keep-alive containers and only hear about the change through their refreshKey. */
  $effect(() => {
    return jobsClient.onJobSettled(() => {
      mediaChanged();
    });
  });

  function openDetailById(id: string) {
    openDetail({ id } as MediaItem);
  }

  function handleKeydown(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      if (!isSearchOpen) {
        openSearch();
      }
      return;
    }

    if (event.key === "Escape" && activeView === "detail" && !isCreateOpen && !isSearchOpen) {
      event.preventDefault();
      closeDetail();
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<AppShell mainRef={(el) => (mainScrollContainer = el)}>
  {#snippet sidebar()}
    <Sidebar
      {activeView}
      onNavigate={navigate}
      onCreate={openCreate}
      onOpenSettings={openSettings}
    />
  {/snippet}

  {#snippet header()}
    <Header title={titleForView(activeView)} onSearch={() => openSearch()} />
  {/snippet}

  {#if renderedView === "lists"}
    {#await import("$views/ListsView.svelte") then { default: ListsView }}
      <ListsView onOpen={openDetail} onImportCompleted={mediaChanged} />
    {:catch error}
      {@const _ = console.error("Failed to load view/modal:", error)}
    {/await}
  {/if}

  <div class:hidden={renderedView !== "home"}>
    <HomeView
      refreshKey={mediaRevision}
      onOpen={openDetail}
      onMediaChanged={mediaChanged}
      onEdit={openEdit}
    />
  </div>

  {#if activeCategory !== null}
    <div class:hidden={renderedView === null || !isCategory(renderedView)}>
      {#key activeCategory}
        <CategoryView
          category={activeCategory}
          active={renderedView !== null && isCategory(renderedView)}
          refreshKey={mediaRevision}
          onOpen={openDetail}
          onMediaChanged={mediaChanged}
          onEdit={openEdit}
        />
      {/key}
    </div>
  {/if}

  {#if renderedView === "detail" && selectedMediaId}
    {#await import("$views/MediaDetailView.svelte") then { default: MediaDetailView }}
      <MediaDetailView
        mediaId={selectedMediaId}
        refreshKey={mediaRevision}
        onBack={closeDetail}
        onUpdate={mediaChanged}
        onDelete={deleteFromDetail}
        onEdit={openEdit}
        onOpenRelated={openDetail}
        onSearch={(context) => openSearch(context)}
      />
    {:catch error}
      {@const _ = console.error("Failed to load view/modal:", error)}
    {/await}
  {:else if renderedView === "seasons" && selectedMediaId}
    {#await import("$views/ShowSeasonsView.svelte") then { default: ShowSeasonsView }}
      <ShowSeasonsView
        mediaId={selectedMediaId}
        refreshKey={mediaRevision}
        onBack={closeDetail}
        onMediaChanged={mediaChanged}
      />
    {:catch error}
      {@const _ = console.error("Failed to load view/modal:", error)}
    {/await}
  {:else if renderedView === "stats"}
    {#await import("$views/StatsView.svelte") then { default: StatsView }}
      <StatsView refreshKey={mediaRevision} onOpenMedia={(mediaId) => openDetailById(mediaId)} />
    {:catch error}
      {@const _ = console.error("Failed to load view/modal:", error)}
    {/await}
  {:else if renderedView === "history"}
    {#await import("$views/HistoryView.svelte") then { default: HistoryView }}
      <HistoryView refreshKey={mediaRevision} onOpenMedia={(mediaId) => openDetailById(mediaId)} />
    {:catch error}
      {@const _ = console.error("Failed to load view/modal:", error)}
    {/await}
  {:else if renderedView === "calendar"}
    {#await import("$views/CalendarView.svelte") then { default: CalendarView }}
      <CalendarView onOpenMedia={(id) => openDetailById(id)} />
    {:catch error}
      {@const _ = console.error("Failed to load view/modal:", error)}
    {/await}
  {/if}
</AppShell>

{#if isCreateOpen}
  {#await import("$features/create-media/CreateModal.svelte") then { default: CreateModal }}
    <CreateModal
      isOpen={isCreateOpen}
      editingItem={editingItem ?? undefined}
      onClose={closeCreate}
      onCreated={handleCreated}
    />
  {:catch error}
    {@const _ = console.error("Failed to load view/modal:", error)}
  {/await}
{/if}
{#if isSearchOpen}
  {#await import("$features/search-external/SearchModal.svelte") then { default: SearchModal }}
    <SearchModal
      isOpen={isSearchOpen}
      initialType={initialSearchType}
      initialQuery={initialSearchQuery}
      initialSource={initialSearchSource}
      byCreator={initialSearchByCreator}
      onClose={closeSearch}
      onMediaAdded={handleCreated}
      onNavigateToMedia={(id) => {
        closeSearch();
        openDetailById(id);
      }}
    />
  {:catch error}
    {@const _ = console.error("Failed to load view/modal:", error)}
  {/await}
{/if}
{#if isSettingsOpen}
  {#await import("$features/settings/SettingsModal.svelte") then { default: SettingsModal }}
    <SettingsModal
      isOpen={isSettingsOpen}
      onClose={closeSettings}
      onImportCompleted={mediaChanged}
      onNavigateToList={navigateToList}
    />
  {:catch error}
    {@const _ = console.error("Failed to load view/modal:", error)}
  {/await}
{/if}
{#if dropPromptState.target !== null}
  {#await import("$features/drop-reason/DropReasonModal.svelte") then { default: DropReasonModal }}
    <DropReasonModal />
  {:catch error}
    {@const _ = console.error("Failed to load view/modal:", error)}
  {/await}
{/if}
{#if jobsClient.isModalOpen}
  {#await import("$widgets/layout/BackgroundJobsModal.svelte") then { default: BackgroundJobsModal }}
    <BackgroundJobsModal onMediaChanged={mediaChanged} />
  {:catch error}
    {@const _ = console.error("Failed to load view/modal:", error)}
  {/await}
{/if}

<FirstRunStorageModal />
