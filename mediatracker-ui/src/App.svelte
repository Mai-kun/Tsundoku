<script lang="ts">
  import { deleteMedia } from '$lib/api'
  import AppShell from '$lib/components/layout/AppShell.svelte'
  import Header from '$lib/components/layout/Header.svelte'
  import Sidebar from '$lib/components/layout/Sidebar.svelte'
  import CreateModal from '$lib/components/modals/CreateModal.svelte'
  import SearchModal from '$lib/components/modals/SearchModal.svelte'
  import SettingsModal from '$lib/components/modals/SettingsModal.svelte'
  import CalendarView from '$lib/components/views/CalendarView.svelte'
  import CategoryView, { type Category } from '$lib/components/views/CategoryView.svelte'
  import HomeView from '$lib/components/views/HomeView.svelte'
  import ListsView from '$lib/components/views/ListsView.svelte'
  import MediaDetailView from '$lib/components/views/MediaDetailView.svelte'
  import ShowSeasonsView from '$lib/components/views/ShowSeasonsView.svelte'
  import StatsView from '$lib/components/views/StatsView.svelte'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { AppView, MediaItem, SearchScope } from '$lib/types'

  const categories: readonly Category[] = ['tvshow', 'movie', 'anime', 'manga', 'game', 'book']
  const views: readonly AppView[] = ['home', ...categories, 'stats', 'lists', 'calendar', 'seasons', 'detail']

  let route = readRoute()
  let activeView = $state<AppView>(route.view)
  let previousView = $state<AppView>(route.view === 'seasons' || route.view === 'detail' ? 'home' : route.view)
  let selectedMediaId = $state<string | null>(route.mediaId)
  let isCreateOpen = $state(false)
  let editingItem = $state<MediaItem | null>(null)
  let isSearchOpen = $state(false)
  let isSettingsOpen = $state(false)
  let initialSearchType = $state<SearchScope>('all')
  let mediaRevision = $state(0)
  let modalTrigger = $state<HTMLElement | null>(null)
  let detailDepth = 0
  let mainScrollContainer = $state<HTMLElement | null>(null)
  const savedScrollPositions = new Map<string, number>()

  function restoreScroll(view: string) {
    const saved = savedScrollPositions.get(view)
    if (typeof saved === 'number') {
      setTimeout(() => {
        if (mainScrollContainer) mainScrollContainer.scrollTop = saved
        window.scrollTo(0, saved)
      }, 50)
    }
  }

  $effect(() => {
    const syncFromHistory = () => {
      const nextRoute = readRoute()
      activeView = nextRoute.view
      selectedMediaId = nextRoute.mediaId
      if (nextRoute.view !== 'detail') {
        detailDepth = 0
        restoreScroll(nextRoute.view)
      }
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
    const requiresMedia = view === 'seasons' || view === 'detail'
    const mediaId = requiresMedia ? parameters.get('mediaId') : null

    return mediaId || !requiresMedia ? { view, mediaId } : { view: 'home', mediaId: null }
  }

  function writeRoute(view: AppView, mediaId: string | null) {
    const url = new URL(window.location.href)
    url.searchParams.set('view', view)

    if ((view === 'seasons' || view === 'detail') && mediaId) {
      url.searchParams.set('mediaId', mediaId)
    } else {
      url.searchParams.delete('mediaId')
    }

    window.history.pushState(null, '', url)
  }

  function navigate(view: AppView) {
    activeView = view
    selectedMediaId = null
    detailDepth = 0
    writeRoute(view, null)
  }

  function openDetail(item: MediaItem) {
    if (activeView !== 'detail') {
      previousView = activeView
      const currentScroll = mainScrollContainer ? mainScrollContainer.scrollTop : (typeof window !== 'undefined' ? window.scrollY : 0)
      savedScrollPositions.set(activeView, currentScroll)
    }

    activeView = 'detail'
    selectedMediaId = item.id
    writeRoute('detail', item.id)
    detailDepth += 1
  }

  function closeDetail() {
    const target = previousView
    if (detailDepth > 0) {
      detailDepth -= 1
      window.history.back()
    } else {
      navigate(target)
    }
    restoreScroll(target)
  }

  async function deleteFromDetail(id: string) {
    await deleteMedia(id)
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
      case 'detail':
        return i18n.t.detail.eyebrow
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

  function openSettings() {
    rememberTrigger()
    isSettingsOpen = true
  }

  function closeSettings() {
    isSettingsOpen = false
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
      return
    }

    if (event.key === 'Escape' && activeView === 'detail' && !isCreateOpen && !isSearchOpen) {
      event.preventDefault()
      closeDetail()
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<AppShell mainRef={(el) => (mainScrollContainer = el)}>
  {#snippet sidebar()}
    <Sidebar {activeView} onNavigate={navigate} onCreate={openCreate} onOpenSettings={openSettings} />
  {/snippet}

  {#snippet header()}
    <Header title={titleForView(activeView)} onSearch={openSearch} />
  {/snippet}

  {#key activeView}
    {#if activeView === 'home'}
      <HomeView refreshKey={mediaRevision} onOpen={openDetail} onMediaChanged={mediaChanged} onEdit={openEdit} />
    {:else if activeView === 'detail' && selectedMediaId}
      <MediaDetailView mediaId={selectedMediaId} refreshKey={mediaRevision} onBack={closeDetail} onUpdate={mediaChanged} onDelete={deleteFromDetail} onEdit={openEdit} onOpenRelated={openDetail} />
    {:else if activeView === 'seasons' && selectedMediaId}
      <ShowSeasonsView mediaId={selectedMediaId} refreshKey={mediaRevision} onBack={closeDetail} onMediaChanged={mediaChanged} />
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
<SettingsModal isOpen={isSettingsOpen} onClose={closeSettings} />
