<script lang="ts">
  import { ChevronDown, Languages, Search } from "$shared/ui/Icons.svelte";
  import { i18n, locales, type Locale } from "$shared/i18n/index.svelte";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import ActivityDropdown from "./ActivityDropdown.svelte";

  interface Props {
    title: string;
    onSearch: () => void;
  }

  let { title, onSearch }: Props = $props();

  const localeOptions = locales.map((locale) => ({
    value: locale,
    label: locale.toUpperCase(),
  }));
</script>

<div class="flex h-full items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
  <h1 class="text-ink min-w-0 flex-1 truncate text-base font-semibold tracking-tight">
    {title}
  </h1>

  <div class="flex shrink-0 items-center gap-2">
    <button
      type="button"
      class="bg-elevated hover:bg-card-hover hidden h-9 w-64 items-center gap-2 rounded-lg border border-white/[0.08] px-3 text-left text-sm text-white transition hover:border-indigo-500/40 focus:ring-1 focus:ring-indigo-500/30 focus:outline-none sm:flex"
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
      class="bg-elevated text-muted hover:text-ink inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/[0.08] transition hover:border-indigo-500/40 focus:ring-1 focus:ring-indigo-500/30 focus:outline-none sm:hidden"
      aria-label={i18n.t.header.searchButton}
      onclick={onSearch}
    >
      <Search size={17} aria-hidden="true" />
    </button>

    <ActivityDropdown />

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
          class="tap bg-elevated text-ink inline-flex h-9 items-center gap-1.5 rounded-lg border border-white/[0.08] px-2.5 text-xs font-semibold transition hover:border-indigo-500/40 hover:text-white focus:ring-1 focus:ring-indigo-500/30 focus:outline-none"
          title={i18n.t.header.language}
        >
          <Languages size={15} class="text-muted" aria-hidden="true" />
          {i18n.current.toUpperCase()}
          <ChevronDown size={14} class="text-muted" aria-hidden="true" />
        </button>
      {/snippet}
    </PopoverMenu>
  </div>
</div>
