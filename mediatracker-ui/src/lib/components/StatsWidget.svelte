<script>
  import { onMount } from 'svelte'
  import { i18n } from '$lib/i18n/index.svelte'

  let { stats } = $props()

  let collapsed = $state(false)

  onMount(() => {
    collapsed = localStorage.getItem('mediatracker:stats-collapsed') === 'true'
  })

  function toggle() {
    collapsed = !collapsed
    localStorage.setItem('mediatracker:stats-collapsed', String(collapsed))
  }
</script>

<section class="mt-6 rounded-xl border border-slate-800/80 bg-slate-900/60 p-3" aria-label={i18n.t.stats.ariaLabel}>
  <div class="flex items-center justify-between gap-3">
    <div>
      <p class="text-xs font-semibold uppercase tracking-[0.16em] text-slate-400">{i18n.t.stats.title}</p>
      <p class="mt-0.5 text-sm font-medium text-slate-200">{stats.totalItems} {i18n.t.stats.totalItems}</p>
    </div>
    <button
      type="button"
      class="inline-flex h-8 w-8 items-center justify-center rounded-lg text-slate-400 transition hover:bg-slate-800 hover:text-white focus:outline-none focus:ring-2 focus:ring-blue-400"
      aria-label={collapsed ? i18n.t.stats.expand : i18n.t.stats.collapse}
      aria-expanded={!collapsed}
      aria-controls="media-stats"
      onclick={toggle}
    >
      <svg viewBox="0 0 24 24" class={`h-4 w-4 transition-transform ${collapsed ? '' : 'rotate-180'}`} fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="m6 9 6 6 6-6" />
      </svg>
    </button>
  </div>

  {#if !collapsed}
    <div id="media-stats" class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <article class="rounded-xl border border-slate-800/80 bg-slate-900/60 p-3">
        <div class="flex items-start gap-3">
          <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-violet-500/15 text-violet-300">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path d="M6.5 8.5h11A3.5 3.5 0 0 1 21 12v1.5a3 3 0 0 1-3 3h-1.5l-2-2h-5l-2 2H6a3 3 0 0 1-3-3V12a3.5 3.5 0 0 1 3.5-3.5Z" />
              <path d="M8 12h3m-1.5-1.5v3M16.5 11.25h.01M18.5 13h.01" />
            </svg>
          </div>
          <div>
            <p class="text-sm font-semibold text-slate-100">{i18n.t.tabs.game}</p>
            <p class="mt-1 text-xs text-slate-300">{stats.completedGamesCount} {i18n.t.stats.gamesCompleted}</p>
            <p class="text-xs text-slate-500">{stats.totalHoursPlayed} {i18n.t.stats.hoursInGame}</p>
          </div>
        </div>
      </article>

      <article class="rounded-xl border border-slate-800/80 bg-slate-900/60 p-3">
        <div class="flex items-start gap-3">
          <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-amber-500/15 text-amber-300">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path d="M5 4.5h11.5A2.5 2.5 0 0 1 19 7v12.5H7.5A2.5 2.5 0 0 1 5 17V4.5Z" />
              <path d="M7.5 6.5H19M9 10h6M9 13h6" />
            </svg>
          </div>
          <div>
            <p class="text-sm font-semibold text-slate-100">{i18n.t.tabs.book}</p>
            <p class="mt-1 text-xs text-slate-300">{stats.completedBooksCount} {i18n.t.stats.booksRead}</p>
            <p class="text-xs text-slate-500">{stats.totalPagesRead} {i18n.t.stats.pagesRead}</p>
          </div>
        </div>
      </article>

      <article class="rounded-xl border border-slate-800/80 bg-slate-900/60 p-3">
        <div class="flex items-start gap-3">
          <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-pink-500/15 text-pink-300">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path d="M8 3h8v18H8a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Z" />
              <path d="M16 6h1a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-1M8 8h5M8 12h5M8 16h3" />
            </svg>
          </div>
          <div>
            <p class="text-sm font-semibold text-slate-100">{i18n.t.tabs.manga}</p>
            <p class="mt-1 text-xs text-slate-300">{stats.totalChaptersRead} {i18n.t.stats.chapters}</p>
            <p class="text-xs text-slate-500">{i18n.t.stats.chaptersRead}</p>
          </div>
        </div>
      </article>

      <article class="rounded-xl border border-slate-800/80 bg-slate-900/60 p-3">
        <div class="flex items-start gap-3">
          <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-cyan-500/15 text-cyan-300">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <rect x="3" y="5" width="18" height="14" rx="2" />
              <path d="m7 5 2 4-2 4m10-8-2 4 2 4M11 9h2v6h-2z" />
            </svg>
          </div>
          <div>
            <p class="text-sm font-semibold text-slate-100">{i18n.t.stats.cinema}</p>
            <p class="mt-1 text-xs text-slate-300">{stats.completedMoviesCount} {i18n.t.stats.movies}</p>
            <p class="text-xs text-slate-500">{stats.totalEpisodesWatched} {i18n.t.stats.episodes}</p>
          </div>
        </div>
      </article>
    </div>
  {/if}
</section>
