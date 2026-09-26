<script lang="ts">
  import { deleteMedia } from '$lib/api'
  import AppShell from '$lib/components/layout/AppShell.svelte'
  import Header from '$lib/components/layout/Header.svelte'
  import Sidebar from '$lib/components/layout/Sidebar.svelte'
  import CreateModal from '$lib/components/modals/CreateModal.svelte'
  import MediaDetailModal from '$lib/components/modals/MediaDetailModal.svelte'
  import SearchModal from '$lib/components/modals/SearchModal.svelte'
  import CalendarView from '$lib/components/views/CalendarView.svelte'
  import CategoryView, { type Category } from '$lib/components/views/CategoryView.svelte'
  import HomeView from '$lib/components/views/HomeView.svelte'
  import ListsView from '$lib/components/views/ListsView.svelte'
  import ShowSeasonsView from '$lib/components/views/ShowSeasonsView.svelte'
  import StatsView from '$lib/components/views/StatsView.svelte'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { AppView, MediaItem, SearchScope } from '$lib/types'

  const categories: readonly Category[] = ['tvshow', 'movie', 'anime', 'manga', 'game', 'book']
  const views: readonly AppView[] = ['home', ...categories, 'stats', 'lists', 'calendar', 'seasons']

  let route = readRoute()
  let activeView = $state<AppView>(route.view)
  let previousView = $state<AppView>(route.view === 'seasons' ? 'home' : route.view)
  let selectedTvShowId = $state<string | null>(route.mediaId)
  let isCreateOpen = $state(false)
  let editingItem = $state<MediaItem | null>(null)
  let detailItem = $state<MediaItem | null>(null)
  let isSearchOpen = $state(false)
  let initialSearchType = $state<SearchScope>('all')
  let mediaRevision = $state(0)
  let modalTrigger = $state<HTMLElement | null>(null)

  $effect(() => {
    const syncFromHistory = () => {
      const nextRoute = readRoute()
      activeView = nextRoute.view
      selectedTvShowId = nextRoute.mediaId
    }

    window.addEventListener('popstate', syncFromHistory)
    return () => window.removeEventListener('popstate', syncFromHistory)
  })

  function readRoute(): { view: AppView; mediaId: string | null } {
    if (typeof window === 'undefined') {
      return { view: 'home', mediaId: null }
    }

    const parameters = new URLSearchParams(window.location.search)
    const candidate = parameters.get('view')
    const view = candidate && views.includes(candidate as AppView) ? (candidate as AppView) : 'home'
    const mediaId = view === 'seasons' ? parameters.get('mediaId') : null

    return mediaId || view !== 'seasons' ? { view, mediaId } : { view: 'home', mediaId: null }
  }

  function writeRoute(view: AppView, mediaId: string | null) {
    const url = new URL(window.location.href)
    url.searchParams.set('view', view)

    if (view === 'seasons' && mediaId) {
      url.searchParams.set('mediaId', mediaId)
    } else {
      url.searchParams.delete('mediaId')
    }

    window.history.pushState(null, '', url)
  }

  function navigate(view: AppView) {
    activeView = view
    selectedTvShowId = null
    writeRoute(view, null)
  }

  function openTvShow(id: string) {
    if (activeView !== 'seasons') {
      previousView = activeView
    }

    activeView = 'seasons'
    selectedTvShowId = id
    writeRoute('seasons', id)
  }

  function openDetail(item: MediaItem) {
    previousView = activeView
    detailItem = item
  }

  function closeDetail() {
    detailItem = null

    if (activeView !== previousView) {
      navigate(previousView)
    } else {
      restoreModalFocus()
    }
  }

  function openSeasons(id: string) {
    detailItem = null
    openTvShow(id)
  }

  function editFromDetail(item: MediaItem) {
    detailItem = null
    openEdit(item)
  }

  async function deleteFromDetail(item: MediaItem) {
    await deleteMedia(item.id)
    mediaChanged()
  }

  function titleForView(view: AppView): string {
    switch (view) {
      case 'home':
        return i18n.t.views.homeTitle
      case 'stats':
        return i18n.t.stats.title
      case 'lists':
        return i18n.t.views.listsTitle
      case 'calendar':
        return i18n.t.views.calendarTitle
      case 'seasons':
        return i18n.t.navigation.seasons
      case 'anime':
        return i18n.t.navigation.anime
      default:
        return i18n.t.navigation[view]
    }
  }

  function isCategory(view: AppView): view is Category {
    return categories.includes(view as Category)
  }

  function searchTypeForView(view: AppView): SearchScope {
    return isCategory(view) ? view : 'all'
  }

  function rememberTrigger() {
    modalTrigger = document.activeElement instanceof HTMLElement ? document.activeElement : null
  }

  function restoreModalFocus() {
    const trigger = modalTrigger
    modalTrigger = null
    requestAnimationFrame(() => trigger?.focus())
  }

  function openCreate() {
    rememberTrigger()
    editingItem = null
    isCreateOpen = true
  }

  function openEdit(item: MediaItem) {
    rememberTrigger()
    editingItem = item
    isCreateOpen = true
  }

  function closeCreate() {
    isCreateOpen = false
    editingItem = null
    restoreModalFocus()
  }

  function openSearch() {
    rememberTrigger()
    initialSearchType = searchTypeForView(activeView)
    isSearchOpen = true
  }

  function closeSearch() {
    isSearchOpen = false
    restoreModalFocus()
  }

  function mediaChanged() {
    mediaRevision += 1
  }

  function handleCreated(_: MediaItem) {
    mediaChanged()
  }

  function handleKeydown(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault()
      if (!isSearchOpen) {
        openSearch()
      }
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<AppShell>
  {#snippet sidebar()}
    <Sidebar {activeView} onNavigate={navigate} onCreate={openCreate} />
  {/snippet}

  {#snippet header()}
    <Header title={titleForView(activeView)} onSearch={openSearch} onCreate={openCreate} />
  {/snippet}

  {#key activeView}
    {#if activeView === 'home'}
      <HomeView refreshKey={mediaRevision} onOpen={openDetail} onMediaChanged={mediaChanged} onEdit={openEdit} />
    {:else if activeView === 'seasons' && selectedTvShowId}
      <ShowSeasonsView mediaId={selectedTvShowId} refreshKey={mediaRevision} onBack={() => navigate(previousView)} onMediaChanged={mediaChanged} />
    {:else if activeView === 'stats'}
      <StatsView refreshKey={mediaRevision} />
    {:else if activeView === 'calendar'}
      <CalendarView refreshKey={mediaRevision} />
    {:else if activeView === 'lists'}
      <ListsView />
    {:else if isCategory(activeView)}
      <CategoryView category={activeView} refreshKey={mediaRevision} onOpen={openDetail} onMediaChanged={mediaChanged} onEdit={openEdit} />
    {/if}
  {/key}
</AppShell>

<CreateModal isOpen={isCreateOpen} editingItem={editingItem ?? undefined} onClose={closeCreate} onCreated={handleCreated} />
<SearchModal isOpen={isSearchOpen} initialType={initialSearchType} onClose={closeSearch} onMediaAdded={handleCreated} />
<MediaDetailModal item={detailItem} onClose={closeDetail} onEdit={editFromDetail} onDelete={deleteFromDetail} onOpenSeasons={openSeasons} />
