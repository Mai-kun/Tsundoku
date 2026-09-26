<script lang="ts">
  import { Search } from 'lucide-svelte'
  import { i18n, locales, type Locale } from '$lib/i18n/index.svelte'

  interface Props {
    title: string
    onSearch: () => void
  }

  let { title, onSearch }: Props = $props()

  function changeLocale(event: Event) {
    i18n.setLocale((event.currentTarget as HTMLSelectElement).value as Locale)
  }
</script>

<div class="flex h-full items-center gap-3 px-4 sm:px-6 lg:px-8">
  <h1 class="min-w-0 flex-1 truncate text-base font-semibold tracking-tight text-ink">{title}</h1>

  <button
    type="button"
    class="hidden h-9 w-full max-w-xs items-center gap-2 rounded-md border border-border bg-card px-3 text-left text-sm text-muted transition hover:text-ink focus:outline-none focus:ring-2 focus:ring-accent sm:flex"
    title={i18n.t.header.searchTooltip}
    onclick={onSearch}
  >
    <Search size={16} aria-hidden="true" />
    <span class="flex-1 truncate">{i18n.t.header.searchButton}</span>
    <kbd class="rounded border border-border bg-canvas px-1.5 py-0.5 text-[10px] font-medium text-muted">Ctrl K</kbd>
  </button>

  <button
    type="button"
    class="inline-flex h-9 w-9 items-center justify-center rounded-md border border-border bg-card text-muted transition hover:text-ink focus:outline-none focus:ring-2 focus:ring-accent sm:hidden"
    aria-label={i18n.t.header.searchButton}
    onclick={onSearch}
  >
    <Search size={17} aria-hidden="true" />
  </button>

  <label class="sr-only" for="language-select">{i18n.t.header.language}</label>
  <select
    id="language-select"
    class="h-9 rounded-md border border-border bg-card px-2 text-xs font-semibold text-ink outline-none transition focus:border-accent focus:ring-2 focus:ring-accent"
    value={i18n.current}
    onchange={changeLocale}
  >
    {#each locales as locale}
      <option value={locale}>{locale.toUpperCase()}</option>
    {/each}
  </select>

</div>
