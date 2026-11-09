<script lang="ts">
  import { ChevronDown, CloudOff, Languages, LoaderCircle, Power, Search } from "$shared/ui/Icons";
  import { i18n, locales, type Locale } from "$shared/i18n/index.svelte";
  import { networkActivity } from "$shared/api/networkActivity.svelte";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import { offlineModeState } from "$shared/api/offlineMode.svelte";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import ActivityDropdown from "./ActivityDropdown.svelte";

  interface Props {
    title: string;
    onSearch: () => void;
    onExitClick?: () => void;
  }

  let { title, onSearch, onExitClick }: Props = $props();

  const localeOptions = locales.map((locale) => ({
    value: locale,
    label: locale.toUpperCase(),
  }));

  const isUpdating = $derived(networkActivity.isLoading || jobsClient.activeJobs.length > 0);
</script>

<div class="relative flex h-full w-full items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
  <!-- Fixed-width title slot: RU/EN titles differ by a few pixels; truncate absorbs
       longer titles without pushing the center search bar. -->
  <h1 class="text-ink w-56 min-w-0 shrink-0 truncate text-base font-semibold tracking-tight">
    {title}
  </h1>

  <!-- Strictly centered search with Activity button anchored to its right -->
  <div class="pointer-events-none absolute left-1/2 flex -translate-x-1/2 items-center">
    <div class="relative flex items-center">
      {#if offlineModeState.isOffline}
        <div
          class="pointer-events-auto mr-2.5 flex items-center gap-1.5 rounded-lg border border-amber-500/30 bg-amber-500/15 px-2.5 py-1 text-xs font-medium text-amber-400 shadow-sm"
          title={i18n.t.header.offlineBadgeTooltip}
        >
          <CloudOff size={15} class="shrink-0 text-amber-400" aria-hidden="true" />
          <span class="hidden text-[11px] font-semibold md:inline"
            >{i18n.t.header.offlineBadgeText}</span
          >
        </div>
      {/if}

      <button
        type="button"
        class="bg-elevated hover:bg-card-hover pointer-events-auto hidden h-9 w-[28rem] items-center gap-2 rounded-lg border border-white/[0.08] px-3 text-left text-sm text-white transition hover:border-indigo-500/40 focus:ring-1 focus:ring-indigo-500/30 focus:outline-none sm:flex sm:w-[32rem]"
        title={i18n.t.header.searchTooltip}
        onclick={onSearch}
      >
        <Search size={16} class="text-muted shrink-0" aria-hidden="true" />
        <span class="min-w-0 flex-1 truncate text-zinc-400">{i18n.t.header.searchButton}</span>
        <kbd
          class="bg-canvas text-muted shrink-0 rounded border border-white/[0.08] px-1.5 py-0.5 text-[10px] font-medium"
          >Ctrl K</kbd
        >
      </button>

      <button
        type="button"
        class="bg-elevated text-muted hover:text-ink pointer-events-auto inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/[0.08] transition hover:border-indigo-500/40 focus:ring-1 focus:ring-indigo-500/30 focus:outline-none sm:hidden"
        aria-label={i18n.t.header.searchButton}
        onclick={onSearch}
      >
        <Search size={17} aria-hidden="true" />
      </button>

      <div class="pointer-events-auto absolute left-full ml-2.5 flex items-center">
        <ActivityDropdown />
      </div>
    </div>
  </div>

  <!-- Right cluster: [ Loading indicator ] -> [ Language selector ] -> [ Power button ] -->
  <div class="flex shrink-0 items-center justify-end gap-2.5">
    {#if isUpdating}
      <div
        class="flex size-9 items-center justify-center text-[var(--color-accent-soft,#818cf8)]"
        title={i18n.t.header.updatingData}
      >
        <LoaderCircle size={16} class="size-4 animate-spin" aria-hidden="true" />
      </div>
    {/if}

    <label class="sr-only" for="language-select">{i18n.t.header.language}</label>
    <PopoverMenu
      id="language-select"
      options={localeOptions}
      selected={i18n.current}
      onSelect={(locale) => i18n.setLocale(locale as Locale)}
      label={i18n.t.header.language}
      placement="bottom-end"
    >
      {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
        <button
          type="button"
          popovertarget={popoverTargetId}
          popovertargetaction="toggle"
          style={isOpen ? `anchor-name: ${anchorName}` : undefined}
          class="tap bg-elevated text-ink inline-flex h-9 w-[88px] items-center justify-between rounded-lg border border-white/[0.08] px-2.5 text-xs font-semibold transition hover:border-indigo-500/40 hover:text-white focus:ring-1 focus:ring-indigo-500/30 focus:outline-none"
          title={i18n.t.header.language}
        >
          <Languages size={15} class="text-muted" aria-hidden="true" />
          {i18n.current.toUpperCase()}
          <ChevronDown size={14} class="text-muted" aria-hidden="true" />
        </button>
      {/snippet}
    </PopoverMenu>

    {#if onExitClick}
      <button
        type="button"
        class="bg-elevated text-muted hover:text-ink inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/[0.08] transition hover:border-rose-400/40 focus:ring-1 focus:ring-rose-500/30 focus:outline-none"
        title={i18n.t.header.exit}
        aria-label={i18n.t.header.exit}
        onclick={onExitClick}
      >
        <Power size={16} class="shrink-0" aria-hidden="true" />
      </button>
    {/if}
  </div>
</div>
