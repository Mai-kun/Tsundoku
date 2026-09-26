<script lang="ts">
  import { Check, ChevronDown, ChevronUp, Eye, EyeOff, Key, Layers, Search, Server, ShieldCheck, X } from 'lucide-svelte'
  import { onMount } from 'svelte'
  import { errorMessage, getCategoryOrder, getSources, saveCategoryOrder, saveSourceKey } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { SourceInfo } from '$lib/types'

  interface Props {
    isOpen: boolean
    onClose: () => void
  }

  let { isOpen, onClose }: Props = $props()

  type Tab = 'sources' | 'search'
  let activeTab = $state<Tab>('sources')

  let sources = $state<SourceInfo[]>([])
  let sourcesLoading = $state(false)
  let sourcesError = $state<unknown>(null)

  let inputKeys = $state<Record<string, string>>({})
  let showKeys = $state<Record<string, boolean>>({})
  let savingKey = $state('')
  let keySuccess = $state<Record<string, string>>({})
  let keyErrors = $state<Record<string, unknown>>({})

  let categoryOrder = $state<string[]>([])
  let orderLoading = $state(false)
  let orderSaving = $state(false)
  let orderSuccess = $state(false)

  const defaultCategories = ['anime', 'movie', 'tvshow', 'manga', 'game', 'book']

  $effect(() => {
    if (isOpen) {
      void loadSources()
      void loadOrder()
    }
  })

  async function loadSources() {
    sourcesLoading = true
    sourcesError = null
    try {
      sources = await getSources()
    } catch (e) {
      sourcesError = e
    } finally {
      sourcesLoading = false
    }
  }

  async function loadOrder() {
    orderLoading = true
    try {
      categoryOrder = await getCategoryOrder()
    } catch {
      categoryOrder = [...defaultCategories]
    } finally {
      orderLoading = false
    }
  }

  async function handleSaveKey(sourceId: string) {
    const key = inputKeys[sourceId]?.trim() ?? ''
    savingKey = sourceId
    keyErrors[sourceId] = null
    keySuccess[sourceId] = ''

    try {
      const res = await saveSourceKey(sourceId, key)
      keySuccess[sourceId] = i18n.t.settingsModal.sources.saved
      // Update local source record
      const s = sources.find((x) => x.id === sourceId)
      if (s) {
        s.hasKey = res.hasKey
        s.isConfigured = res.hasKey
        s.maskedKey = res.maskedKey
      }
      inputKeys[sourceId] = ''
    } catch (e) {
      keyErrors[sourceId] = e
    } finally {
      savingKey = ''
    }
  }

  async function moveCategory(index: number, direction: 'up' | 'down') {
    const newOrder = [...categoryOrder]
    const targetIndex = direction === 'up' ? index - 1 : index + 1
    if (targetIndex < 0 || targetIndex >= newOrder.length) return

    const temp = newOrder[index]
    newOrder[index] = newOrder[targetIndex]
    newOrder[targetIndex] = temp
    categoryOrder = newOrder

    orderSaving = true
    orderSuccess = false
    try {
      await saveCategoryOrder(newOrder)
      orderSuccess = true
      setTimeout(() => (orderSuccess = false), 2000)
    } catch (e) {
      console.error(e)
    } finally {
      orderSaving = false
    }
  }

  function categoryLabel(cat: string): string {
    if (cat === 'anime') return i18n.t.navigation.anime
    return i18n.t.types[cat as keyof typeof i18n.t.types] || cat
  }

  function handleKeydown(event: KeyboardEvent) {
    if (isOpen && event.key === 'Escape') {
      onClose()
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if isOpen}
  <div
    class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-canvas/85 p-4 backdrop-blur-sm sm:items-center"
    role="presentation"
    onclick={(e) => { if (e.target === e.currentTarget) onClose() }}
  >
    <div
      class="my-auto flex min-h-[500px] max-h-[85vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-border bg-surface shadow-2xl shadow-black/60"
      role="dialog"
      aria-modal="true"
      aria-labelledby="settings-title"
    >
      <!-- Header -->
      <header class="flex items-center justify-between border-b border-border px-6 py-4">
        <div class="flex items-center gap-3">
          <div class="grid h-8 w-8 place-items-center rounded-lg bg-card text-accent-soft">
            <Server size={18} />
          </div>
          <div>
            <h2 id="settings-title" class="text-lg font-bold tracking-tight text-ink">{i18n.t.settingsModal.title}</h2>
          </div>
        </div>
        <button
          type="button"
          class="grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink"
          aria-label={i18n.t.common.close}
          onclick={onClose}
        >
          <X size={18} />
        </button>
      </header>

      <!-- Tabs Navigation -->
      <div class="flex border-b border-border bg-card/40 px-6">
        <button
          type="button"
          class={`flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition ${
            activeTab === 'sources'
              ? 'border-accent-soft text-ink'
              : 'border-transparent text-muted hover:text-ink'
          }`}
          onclick={() => (activeTab = 'sources')}
        >
          <ShieldCheck size={16} />
          {i18n.t.settingsModal.tabs.sources}
        </button>
        <button
          type="button"
          class={`flex items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition ${
            activeTab === 'search'
              ? 'border-accent-soft text-ink'
              : 'border-transparent text-muted hover:text-ink'
          }`}
          onclick={() => (activeTab = 'search')}
        >
          <Search size={16} />
          {i18n.t.settingsModal.tabs.search}
        </button>
      </div>

      <!-- Tab Body -->
      <div class="flex-1 overflow-y-auto p-6">
        {#if activeTab === 'sources'}
          <div class="space-y-4">
            <div>
              <h3 class="text-sm font-semibold text-ink">{i18n.t.settingsModal.sources.title}</h3>
              <p class="mt-0.5 text-xs text-muted">{i18n.t.settingsModal.sources.description}</p>
            </div>

            {#if sourcesLoading}
              <div class="space-y-3">
                {#each Array(4) as _, i (i)}
                  <div class="h-24 animate-pulse rounded-lg bg-card"></div>
                {/each}
              </div>
            {:else if sourcesError}
              <p class="rounded-lg bg-rose-400/10 p-3 text-xs text-rose-300">{errorMessage(sourcesError)}</p>
            {:else}
              <div class="space-y-3">
                {#each sources as source (source.id)}
                  <div class="rounded-lg border border-border bg-card p-4 transition">
                    <div class="flex flex-wrap items-start justify-between gap-2">
                      <div>
                        <div class="flex items-center gap-2">
                          <h4 class="text-sm font-bold text-ink">{source.name}</h4>
                          {#if source.requiresApiKey}
                            {#if source.hasKey}
                              <span class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 text-[11px] font-semibold text-emerald-400">
                                <Check size={12} />
                                {i18n.t.settingsModal.sources.keyConfigured}
                              </span>
                            {:else}
                              <span class="inline-flex items-center gap-1 rounded bg-amber-500/15 px-2 py-0.5 text-[11px] font-semibold text-amber-400">
                                <Key size={12} />
                                {i18n.t.settingsModal.sources.keyRequired}
                              </span>
                            {/if}
                          {:else}
                            <span class="inline-flex items-center gap-1 rounded bg-sky-500/15 px-2 py-0.5 text-[11px] font-semibold text-sky-400">
                              <ShieldCheck size={12} />
                              {i18n.t.settingsModal.sources.noKeyRequired}
                            </span>
                          {/if}
                        </div>
                        <p class="mt-1 text-xs text-muted">{source.description}</p>
                        <div class="mt-2 flex flex-wrap gap-1.5">
                          {#each source.mediaTypes as mt}
                            <span class="rounded bg-canvas px-2 py-0.5 text-[10px] font-medium text-muted">
                              {categoryLabel(mt)}
                            </span>
                          {/each}
                        </div>
                      </div>
                    </div>

                    {#if source.requiresApiKey}
                      <div class="mt-3 border-t border-border/60 pt-3">
                        {#if source.maskedKey}
                          <div class="mb-2 flex items-center gap-2 text-xs text-muted">
                            <span>Текущий ключ:</span>
                            <code class="rounded bg-canvas px-2 py-0.5 font-mono text-[11px] text-ink">{source.maskedKey}</code>
                          </div>
                        {/if}

                        <div class="flex flex-wrap items-center gap-2">
                          <div class="relative flex-1 min-w-[200px]">
                            <input
                              type={showKeys[source.id] ? 'text' : 'password'}
                              class="h-9 w-full rounded-md border border-border bg-elevated px-3 pr-9 text-xs text-ink placeholder:text-muted focus:border-accent-soft focus:outline-none focus:ring-1 focus:ring-accent-soft"
                              placeholder={source.hasKey ? 'Заменить API ключ...' : i18n.t.settingsModal.sources.inputPlaceholder}
                              value={inputKeys[source.id] ?? ''}
                              oninput={(e) => (inputKeys[source.id] = (e.currentTarget as HTMLInputElement).value)}
                            />
                            <button
                              type="button"
                              class="absolute right-2 top-1/2 -translate-y-1/2 text-muted hover:text-ink"
                              aria-label="Toggle key visibility"
                              onclick={() => (showKeys[source.id] = !showKeys[source.id])}
                            >
                              {#if showKeys[source.id]}
                                <EyeOff size={14} />
                              {:else}
                                <Eye size={14} />
                              {/if}
                            </button>
                          </div>

                          <button
                            type="button"
                            class="inline-flex h-9 items-center gap-1.5 rounded-md border border-border bg-elevated px-3 text-xs font-semibold text-ink transition hover:bg-card hover:border-accent-soft disabled:cursor-wait disabled:opacity-60"
                            disabled={savingKey === source.id || !inputKeys[source.id]?.trim()}
                            onclick={() => void handleSaveKey(source.id)}
                          >
                            <ShieldCheck size={14} />
                            {savingKey === source.id ? i18n.t.common.saving : i18n.t.settingsModal.sources.saveKey}
                          </button>
                        </div>

                        {#if keySuccess[source.id]}
                          <p class="mt-2 text-xs font-medium text-emerald-400">{keySuccess[source.id]}</p>
                        {/if}
                        {#if keyErrors[source.id]}
                          <p class="mt-2 text-xs text-rose-300">{errorMessage(keyErrors[source.id])}</p>
                        {/if}
                      </div>
                    {/if}
                  </div>
                {/each}
              </div>
            {/if}
          </div>
        {:else if activeTab === 'search'}
          <div class="space-y-4">
            <div>
              <h3 class="text-sm font-semibold text-ink">{i18n.t.settingsModal.search.orderTitle}</h3>
              <p class="mt-0.5 text-xs text-muted">{i18n.t.settingsModal.search.orderHint}</p>
            </div>

            {#if orderLoading}
              <div class="h-32 animate-pulse rounded-lg bg-card"></div>
            {:else}
              <div class="space-y-2">
                {#each categoryOrder as cat, idx (cat)}
                  <div class="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-2.5">
                    <div class="flex items-center gap-3">
                      <span class="grid h-6 w-6 place-items-center rounded bg-canvas text-xs font-bold text-muted">
                        {idx + 1}
                      </span>
                      <span class="text-sm font-medium text-ink">{categoryLabel(cat)}</span>
                    </div>

                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        class="grid h-7 w-7 place-items-center rounded-md text-muted transition hover:bg-elevated hover:text-ink disabled:opacity-30"
                        disabled={idx === 0 || orderSaving}
                        aria-label={i18n.t.settingsModal.search.moveUp}
                        onclick={() => void moveCategory(idx, 'up')}
                      >
                        <ChevronUp size={16} />
                      </button>
                      <button
                        type="button"
                        class="grid h-7 w-7 place-items-center rounded-md text-muted transition hover:bg-elevated hover:text-ink disabled:opacity-30"
                        disabled={idx === categoryOrder.length - 1 || orderSaving}
                        aria-label={i18n.t.settingsModal.search.moveDown}
                        onclick={() => void moveCategory(idx, 'down')}
                      >
                        <ChevronDown size={16} />
                      </button>
                    </div>
                  </div>
                {/each}
              </div>

              {#if orderSuccess}
                <p class="text-xs font-medium text-emerald-400">{i18n.t.settingsModal.search.saved}</p>
              {/if}
            {/if}
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}
