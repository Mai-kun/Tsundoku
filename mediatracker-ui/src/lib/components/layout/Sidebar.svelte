<script lang="ts">
  import { BarChart3, BookOpen, CalendarDays, Film, Gamepad2, History, Home, Library, List, Menu, Plus, Settings, Tv } from 'lucide-svelte'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { AppView } from '$lib/types'

  interface Props {
    activeView: AppView
    onNavigate: (view: AppView) => void
    onCreate: () => void
    onOpenSettings?: () => void
  }

  let { activeView, onNavigate, onCreate, onOpenSettings = () => {} }: Props = $props()

  let toolsOpen = $state(false)

  function navigate(view: AppView) {
    toolsOpen = false
    onNavigate(view)
  }

  function itemClass(view: AppView): string {
    return activeView === view
      ? 'bg-elevated/80 text-ink font-semibold shadow-sm [&>svg]:text-accent-soft'
      : 'text-muted hover:bg-card/50 hover:text-ink [&>svg]:text-muted hover:[&>svg]:text-ink'
  }
</script>

<div class="flex h-full items-center justify-around gap-1 lg:flex-col lg:items-stretch lg:justify-between">
  <div class="flex flex-1 items-center justify-around gap-1 lg:flex-none lg:flex-col lg:items-stretch lg:justify-start">
    <div class="hidden px-3 pb-7 lg:block">
      <p class="text-sm font-bold tracking-tight text-ink">Tsundoku</p>
      <p class="mt-1 text-[10px] font-semibold uppercase tracking-[0.18em] text-muted">{i18n.t.navigation.brand}</p>
    </div>

    <nav class="flex flex-1 items-center justify-around gap-1 lg:flex-none lg:flex-col lg:items-stretch lg:justify-start" aria-label={i18n.t.navigation.mainLabel}>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('home')}`} aria-label={i18n.t.navigation.home} title={i18n.t.navigation.home} onclick={() => navigate('home')}><Home size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.home}</span></button>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('tvshow')}`} aria-label={i18n.t.navigation.tvshow} title={i18n.t.navigation.tvshow} onclick={() => navigate('tvshow')}><Tv size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.tvshow}</span></button>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('movie')}`} aria-label={i18n.t.navigation.movie} title={i18n.t.navigation.movie} onclick={() => navigate('movie')}><Film size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.movie}</span></button>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('anime')}`} aria-label={i18n.t.navigation.anime} title={i18n.t.navigation.anime} onclick={() => navigate('anime')}><Tv size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.anime}</span></button>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('manga')}`} aria-label={i18n.t.navigation.manga} title={i18n.t.navigation.manga} onclick={() => navigate('manga')}><Library size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.manga}</span></button>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('game')}`} aria-label={i18n.t.navigation.game} title={i18n.t.navigation.game} onclick={() => navigate('game')}><Gamepad2 size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.game}</span></button>
      <button type="button" class={`inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass('book')}`} aria-label={i18n.t.navigation.book} title={i18n.t.navigation.book} onclick={() => navigate('book')}><BookOpen size={18} /><span class="hidden text-sm font-medium lg:inline">{i18n.t.navigation.book}</span></button>
    </nav>
  </div>

  <div class="lg:hidden">
    <button
      type="button"
      class="inline-flex h-10 w-10 items-center justify-center rounded-md text-muted transition hover:bg-card hover:text-ink"
      aria-label={i18n.t.navigation.toolsLabel}
      aria-expanded={toolsOpen}
      onclick={() => (toolsOpen = !toolsOpen)}
    >
      <Menu size={18} aria-hidden="true" />
    </button>
  </div>

  {#if toolsOpen}
    <div class="absolute inset-x-2 bottom-full mb-2 space-y-1 rounded-lg border border-border bg-surface p-2 shadow-2xl shadow-black/50 lg:hidden">
      <p class="px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted">{i18n.t.navigation.toolsLabel}</p>
      <button type="button" class="inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium text-muted transition hover:bg-card hover:text-ink" onclick={() => { toolsOpen = false; onCreate() }}><Plus size={18} aria-hidden="true" />{i18n.t.navigation.create}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition ${itemClass('stats')}`} onclick={() => navigate('stats')}><BarChart3 size={18} aria-hidden="true" />{i18n.t.navigation.stats}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition ${itemClass('lists')}`} onclick={() => navigate('lists')}><List size={18} aria-hidden="true" />{i18n.t.navigation.lists}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition ${itemClass('history')}`} onclick={() => navigate('history')}><History size={18} aria-hidden="true" />{i18n.t.navigation.history}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition ${itemClass('calendar')}`} onclick={() => navigate('calendar')}><CalendarDays size={18} aria-hidden="true" />{i18n.t.navigation.calendar}</button>
      <button type="button" class="inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium text-muted transition hover:bg-card hover:text-ink" onclick={() => { toolsOpen = false; onOpenSettings() }}><Settings size={18} aria-hidden="true" />{i18n.t.navigation.settings}</button>
    </div>
  {/if}

  <div class="hidden border-t border-border pt-4 lg:mt-auto lg:block">
    <p class="px-3 pb-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-muted">{i18n.t.navigation.toolsLabel}</p>
    <div class="space-y-1">
      <button type="button" class="inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-muted transition hover:bg-card hover:text-ink" onclick={onCreate}><Plus size={17} />{i18n.t.navigation.create}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition ${itemClass('stats')}`} onclick={() => navigate('stats')}><BarChart3 size={17} />{i18n.t.navigation.stats}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition ${itemClass('lists')}`} onclick={() => navigate('lists')}><List size={17} />{i18n.t.navigation.lists}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition ${itemClass('history')}`} onclick={() => navigate('history')}><History size={17} />{i18n.t.navigation.history}</button>
      <button type="button" class={`inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition ${itemClass('calendar')}`} onclick={() => navigate('calendar')}><CalendarDays size={17} />{i18n.t.navigation.calendar}</button>
      <button type="button" class="inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-muted transition hover:bg-card hover:text-ink" onclick={onOpenSettings}><Settings size={17} />{i18n.t.navigation.settings}</button>
    </div>
  </div>
</div>
