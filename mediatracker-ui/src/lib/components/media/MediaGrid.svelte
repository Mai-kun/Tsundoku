<script lang="ts">
  import { Inbox, RefreshCw } from 'lucide-svelte'
  import { errorMessage } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { MediaItem } from '$lib/types'
  import MediaCard from './MediaCard.svelte'

  interface Props {
    items: MediaItem[]
    loading?: boolean
    error?: unknown
    onRetry?: () => void
    onOpen?: (item: MediaItem) => void
    onProgress?: (id: string, currentProgress: number) => Promise<void>
    onProgressCommitted?: () => void
    onDelete?: (item: MediaItem) => Promise<void>
    onEdit?: (item: MediaItem) => void
  }

  let {
    items,
    loading = false,
    error = null,
    onRetry = () => {},
    onOpen = () => {},
    onProgress,
    onProgressCommitted = () => {},
    onDelete,
    onEdit = () => {},
  }: Props = $props()
</script>

{#if loading}
  <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6" aria-hidden="true">
    {#each Array(6) as _, index (index)}
      <div class="overflow-hidden rounded-2xl border border-border bg-surface">
        <div class="aspect-[3/4] animate-pulse bg-elevated"></div>
        <div class="space-y-2 p-3.5">
          <div class="h-4 w-3/4 animate-pulse rounded bg-elevated"></div>
          <div class="h-3 w-1/2 animate-pulse rounded bg-elevated"></div>
        </div>
      </div>
    {/each}
  </div>
  <p class="sr-only" role="status">{i18n.t.common.loading}</p>
{:else if error}
  <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-2xl border border-rose-400/25 bg-rose-400/5 p-6 text-center">
    <p class="text-sm text-rose-200" role="alert">{errorMessage(error)}</p>
    <button type="button" class="inline-flex items-center gap-2 rounded-lg border border-border bg-surface px-3 py-2 text-sm font-semibold text-ink transition hover:border-accent/50" onclick={onRetry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button>
  </div>
{:else if items.length === 0}
  <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-2xl border border-dashed border-border bg-surface/60 p-6 text-center">
    <div class="grid h-12 w-12 place-items-center rounded-2xl bg-elevated text-muted"><Inbox size={22} aria-hidden="true" /></div>
    <div>
      <p class="font-semibold text-ink">{i18n.t.library.emptyTitle}</p>
      <p class="mt-1 max-w-sm text-sm text-muted">{i18n.t.library.emptyHint}</p>
    </div>
  </div>
{:else}
  <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
    {#each items as item (item.id)}
      <MediaCard {item} {onOpen} {onProgress} {onProgressCommitted} {onDelete} {onEdit} />
    {/each}
  </div>
{/if}
