<script lang="ts">
  import { i18n } from '$lib/i18n/index.svelte'
  import type { MediaStats, StatusFilter } from '$lib/types'

  type StatusKey = 'all' | 'planned' | 'inProgress' | 'completed' | 'dropped'
  type SortKey = 'newest' | 'oldest' | 'rating' | 'title'

  interface StatusOption {
    id: StatusFilter
    key: StatusKey
    countKey?: keyof MediaStats
    activeClass: string
  }

  interface SortOption {
    value: string
    key: SortKey
  }

  interface Props {
    status: StatusFilter
    sort: string
    counts?: Partial<MediaStats>
    onStatusChange?: (status: StatusFilter) => void
    onSortChange?: (sort: string) => void
  }

  const statusOptions: StatusOption[] = [
    { id: 'all', key: 'all', countKey: 'totalItems', activeClass: 'border-blue-400/60 bg-blue-500/15 text-blue-200' },
    { id: 1, key: 'inProgress', countKey: 'inProgressItems', activeClass: 'border-blue-400/60 bg-blue-500/15 text-blue-200' },
    { id: 0, key: 'planned', countKey: 'plannedItems', activeClass: 'border-slate-500 bg-slate-700 text-slate-100' },
    { id: 2, key: 'completed', countKey: 'completedItems', activeClass: 'border-emerald-400/60 bg-emerald-500/15 text-emerald-200' },
    { id: 4, key: 'dropped', activeClass: 'border-rose-400/60 bg-rose-500/15 text-rose-200' },
  ]

  const sortOptions: SortOption[] = [
    { value: 'createdAt:desc', key: 'newest' },
    { value: 'createdAt:asc', key: 'oldest' },
    { value: 'score:desc', key: 'rating' },
    { value: 'title:asc', key: 'title' },
  ]

  let { status, sort, counts = {}, onStatusChange = () => {}, onSortChange = () => {} }: Props = $props()
</script>

<div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
  <nav class="flex flex-wrap gap-2" aria-label={i18n.t.status.label}>
    {#each statusOptions as option}
      {@const count = option.countKey ? counts[option.countKey] : undefined}
      <button
        type="button"
        class={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold transition focus:outline-none focus:ring-2 focus:ring-blue-400 ${status === option.id ? option.activeClass : 'border-slate-700 bg-slate-900/40 text-slate-400 hover:border-slate-600 hover:text-slate-200'}`}
        aria-pressed={status === option.id}
        onclick={() => onStatusChange(option.id)}
      >
        {i18n.t.status[option.key]}
        {#if count !== undefined}
          <span class={`rounded-full px-1.5 py-0.5 text-[10px] ${status === option.id ? 'bg-slate-950/25' : 'bg-slate-800 text-slate-500'}`}>{count}</span>
        {/if}
      </button>
    {/each}
  </nav>

  <label class="flex shrink-0 items-center gap-2 text-xs font-medium text-slate-400">
    <span>{i18n.t.sort.label}</span>
    <select
      class="rounded-lg border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-medium text-slate-200 outline-none transition hover:border-slate-600 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/20"
      value={sort}
      onchange={(event) => onSortChange(event.currentTarget.value)}
    >
      {#each sortOptions as option}
        <option value={option.value}>{i18n.t.sort[option.key]}</option>
      {/each}
    </select>
  </label>
</div>
