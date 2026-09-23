<script>
  const statusOptions = [
    { id: 'all', label: 'Все', countKey: 'totalItems', activeClass: 'border-blue-400/60 bg-blue-500/15 text-blue-200' },
    { id: 1, label: 'В процессе', countKey: 'inProgressItems', activeClass: 'border-blue-400/60 bg-blue-500/15 text-blue-200' },
    { id: 0, label: 'В планах', countKey: 'plannedItems', activeClass: 'border-slate-500 bg-slate-700 text-slate-100' },
    { id: 2, label: 'Завершено', countKey: 'completedItems', activeClass: 'border-emerald-400/60 bg-emerald-500/15 text-emerald-200' },
    { id: 4, label: 'Брошено', activeClass: 'border-rose-400/60 bg-rose-500/15 text-rose-200' },
  ]

  let { status, sort, counts = {}, onStatusChange = () => {}, onSortChange = () => {} } = $props()
</script>

<div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
  <nav class="flex flex-wrap gap-2" aria-label="Статус">
    {#each statusOptions as option}
      {@const count = option.countKey ? counts[option.countKey] : undefined}
      <button
        type="button"
        class={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold transition focus:outline-none focus:ring-2 focus:ring-blue-400 ${status === option.id ? option.activeClass : 'border-slate-700 bg-slate-900/40 text-slate-400 hover:border-slate-600 hover:text-slate-200'}`}
        aria-pressed={status === option.id}
        onclick={() => onStatusChange(option.id)}
      >
        {option.label}
        {#if count !== undefined}
          <span class={`rounded-full px-1.5 py-0.5 text-[10px] ${status === option.id ? 'bg-slate-950/25' : 'bg-slate-800 text-slate-500'}`}>{count}</span>
        {/if}
      </button>
    {/each}
  </nav>

  <label class="flex shrink-0 items-center gap-2 text-xs font-medium text-slate-400">
    <span>Сортировка</span>
    <select
      class="rounded-lg border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-medium text-slate-200 outline-none transition hover:border-slate-600 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/20"
      value={sort}
      onchange={(event) => onSortChange(event.currentTarget.value)}
    >
      <option value="createdAt:desc">Сначала новые добавленные</option>
      <option value="createdAt:asc">Сначала старые</option>
      <option value="score:desc">По рейтингу (сначала высокий)</option>
      <option value="title:asc">По названию (А - Я)</option>
    </select>
  </label>
</div>
