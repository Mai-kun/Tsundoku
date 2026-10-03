<script lang="ts">
    import { flushSync } from "svelte";
import { deleteMedia } from "$shared/api/api";
    import { jobsClient } from "$shared/api/jobsClient.svelte";
    import AppShell from "$widgets/layout/AppShell.svelte";
    import Header from "$widgets/layout/Header.svelte";
    import Sidebar from "$widgets/layout/Sidebar.svelte";
    import CreateModal from "$features/create-media/CreateModal.svelte";
    import SearchModal from "$features/search-external/SearchModal.svelte";
    import SettingsModal from "$features/settings/SettingsModal.svelte";
    import CalendarView from "$views/CalendarView.svelte";
    import CategoryView, {
        type Category,
    } from "$views/CategoryView.svelte";
    import HistoryView from "$views/HistoryView.svelte";
    import HomeView from "$views/HomeView.svelte";
    import ListsView from "$views/ListsView.svelte";
    import MediaDetailView from "$views/MediaDetailView.svelte";
    import ShowSeasonsView from "$views/ShowSeasonsView.svelte";
    import StatsView from "$views/StatsView.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AppView, MediaItem, SearchScope } from "$shared/types";

    const categories: readonly Category[] = [
        "tvshow",
        "movie",
        "anime",
        "manga",
        "game",
        "book",
    ];
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
    /* What is actually in the DOM. Svelte mounts an incoming {#if} branch before tearing down the
       outgoing one, so switching views rendered both at once for ~170ms. We drop the rendered view
       to null and force the DOM update with flushSync() before mounting the new one. Both updates
       then happen inside the same task, so the browser only ever paints the final state: it never
       sees the outgoing view, the new view, or an empty area. */
    let renderedView = $state<AppView | null>(route.view);
    /* True while a view swap is in progress. Svelte defers tearing down the outgoing view (~130ms),
       so the new one would otherwise paint on top of it. While switching we hide the view area and
       reveal it again once the stale node is really gone. */
    let switching = $state(false);
    let switchFrame = 0;

    function revealWhenSettled() {
        const main = mainScrollContainer;
        // One child means only the incoming view is left; then it is safe to show it again.
        if (main && main.children.length <= 1) {
            switching = false;
            return;
        }
        switchFrame = requestAnimationFrame(revealWhenSettled);
    }
    let previousView = $state<AppView>(
        route.view === "seasons" || route.view === "detail"
            ? "home"
            : route.view,
    );
    let selectedMediaId = $state<string | null>(route.mediaId);
    let isCreateOpen = $state(false);
    let editingItem = $state<MediaItem | null>(null);
    let isSearchOpen = $state(false);
    let isSettingsOpen = $state(false);
    let initialSearchType = $state<SearchScope>("all");
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
            const nextRoute = readRoute();
            activeView = nextRoute.view;
            selectedMediaId = nextRoute.mediaId;
            switchView(nextRoute.view);
            if (nextRoute.view === "detail") {
                setScroll(0);
            } else {
                detailDepth = 0;
                restoreScroll(nextRoute.view);
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
        const view =
            candidate && views.includes(candidate as AppView)
                ? (candidate as AppView)
                : "home";
        const requiresMedia = view === "seasons" || view === "detail";
        const mediaId = requiresMedia ? parameters.get("mediaId") : null;

        return mediaId || !requiresMedia
            ? { view, mediaId }
            : { view: "home", mediaId: null };
    }

    function writeRoute(view: AppView, mediaId: string | null) {
        const url = new URL(window.location.href);
        url.searchParams.set("view", view);

        if ((view === "seasons" || view === "detail") && mediaId) {
            url.searchParams.set("mediaId", mediaId);
        } else {
            url.searchParams.delete("mediaId");
        }

        window.history.pushState(null, "", url);
    }

    /**
     * Single entry point for changing views. Unmounts the current view and flushes that removal
     * synchronously, then mounts the incoming one. Because both DOM updates run in the same task,
     * the browser paints only the final state -- never two views stacked, never an empty frame.
     */
    function switchView(view: AppView) {
        cancelAnimationFrame(switchFrame);
        switching = true;
        renderedView = null;
        flushSync();
        renderedView = view;
        flushSync();
        // The stale node may still be in the DOM for a few frames; keep the area hidden until it is
        // gone so the incoming view is never painted alongside it.
        switchFrame = requestAnimationFrame(revealWhenSettled);
    }

    function navigate(view: AppView) {
        activeView = view;
        selectedMediaId = null;
        detailDepth = 0;
        writeRoute(view, null);
        switchView(view);
    }

    function openDetail(item: MediaItem) {
        if (activeView !== "detail") {
            previousView = activeView;
            savedScrollPositions.set(
                activeView,
                mainScrollContainer?.scrollTop ?? 0,
            );
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
        modalTrigger =
            document.activeElement instanceof HTMLElement
                ? document.activeElement
                : null;
    }

    function restoreModalFocus() {
        const trigger = modalTrigger;
        modalTrigger = null;
        requestAnimationFrame(() => trigger?.focus());
    }

    function openCreate() {
        rememberTrigger();
        editingItem = null;
        isCreateOpen = true;
    }

    function openEdit(item: MediaItem) {
        rememberTrigger();
        editingItem = item;
        isCreateOpen = true;
    }

    function closeCreate() {
        isCreateOpen = false;
        editingItem = null;
        restoreModalFocus();
    }

    function openSearch() {
        rememberTrigger();
        initialSearchType = "all";
        isSearchOpen = true;
    }

    function closeSearch() {
        isSearchOpen = false;
        restoreModalFocus();
    }

    function openSettings() {
        rememberTrigger();
        isSettingsOpen = true;
    }

    function closeSettings() {
        isSettingsOpen = false;
        restoreModalFocus();
    }

    function mediaChanged() {
        mediaRevision += 1;
    }

    function handleCreated(_: MediaItem) {
        mediaChanged();
    }

    /* A finished background job rewrote the row behind the grid (cover, seasons, sync flag), so the
       lists have to be refetched — otherwise a card keeps its "Syncing" overlay forever. The detail
       screen refreshes itself, so it is skipped here to avoid fetching the same item twice. */
    let settledJobKeys = $state("");
    $effect(() => {
        const settled = jobsClient.jobs
            .filter((job) => job.status === "Completed")
            .map((job) => job.jobId)
            .join(",");

        if (settled === settledJobKeys) return;
        settledJobKeys = settled;
        if (activeView === "detail" || settled === "") return;
        mediaChanged();
    });

    function openDetailById(id: string) {
        openDetail({ id } as MediaItem);
    }

    function handleKeydown(event: KeyboardEvent) {
        if (
            (event.ctrlKey || event.metaKey) &&
            event.key.toLowerCase() === "k"
        ) {
            event.preventDefault();
            if (!isSearchOpen) {
                openSearch();
            }
            return;
        }

        if (
            event.key === "Escape" &&
            activeView === "detail" &&
            !isCreateOpen &&
            !isSearchOpen
        ) {
            event.preventDefault();
            closeDetail();
        }
    }
</script>

<svelte:window onkeydown={handleKeydown} />

<AppShell mainRef={(el) => (mainScrollContainer = el)} {switching}>
    {#snippet sidebar()}
        <Sidebar
            {activeView}
            onNavigate={navigate}
            onCreate={openCreate}
            onOpenSettings={openSettings}
        />
    {/snippet}

    {#snippet header()}
        <Header title={titleForView(activeView)} onSearch={openSearch} />
    {/snippet}

    {#if renderedView === "home"}
        <HomeView
            refreshKey={mediaRevision}
            onOpen={openDetail}
            onMediaChanged={mediaChanged}
            onEdit={openEdit}
        />
    {:else if renderedView === "detail" && selectedMediaId}
        <MediaDetailView
            mediaId={selectedMediaId}
            refreshKey={mediaRevision}
            onBack={closeDetail}
            onUpdate={mediaChanged}
            onDelete={deleteFromDetail}
            onEdit={openEdit}
            onOpenRelated={openDetail}
        />
    {:else if renderedView === "seasons" && selectedMediaId}
        <ShowSeasonsView
            mediaId={selectedMediaId}
            refreshKey={mediaRevision}
            onBack={closeDetail}
            onMediaChanged={mediaChanged}
        />
    {:else if renderedView === "stats"}
        <StatsView refreshKey={mediaRevision} />
    {:else if renderedView === "history"}
        <HistoryView refreshKey={mediaRevision} />
    {:else if renderedView === "calendar"}
        <CalendarView />
    {:else if renderedView === "lists"}
        <ListsView />
    {:else if renderedView !== null && isCategory(renderedView)}
        <!-- No {#key} here: keying the whole view remounted it on every switch. The section
             {#each} keys in CategoryView are category-scoped instead, so sections rebuild only
             when their contents actually differ. renderedView already guarantees a single
             mounted view at a time. -->
        <CategoryView
            category={renderedView}
            refreshKey={mediaRevision}
            onOpen={openDetail}
            onMediaChanged={mediaChanged}
            onEdit={openEdit}
        />
    {/if}
</AppShell>

<CreateModal
    isOpen={isCreateOpen}
    editingItem={editingItem ?? undefined}
    onClose={closeCreate}
    onCreated={handleCreated}
/>
<SearchModal
    isOpen={isSearchOpen}
    initialType={initialSearchType}
    onClose={closeSearch}
    onMediaAdded={handleCreated}
    onNavigateToMedia={(id) => {
        closeSearch();
        openDetailById(id);
    }}
/>
<SettingsModal isOpen={isSettingsOpen} onClose={closeSettings} />
