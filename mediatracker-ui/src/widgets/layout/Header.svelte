<script lang="ts">
    import { Search } from "$shared/ui/Icons.svelte";
    import { i18n, locales, type Locale } from "$shared/i18n/index.svelte";
    import ActivityDropdown from "./ActivityDropdown.svelte";

    interface Props {
        title: string;
        onSearch: () => void;
    }

    let { title, onSearch }: Props = $props();

    function changeLocale(event: Event) {
        i18n.setLocale(
            (event.currentTarget as HTMLSelectElement).value as Locale,
        );
    }
</script>

<div
    class="flex h-full items-center justify-between gap-4 px-4 sm:px-6 lg:px-8"
>
    <h1
        class="min-w-0 flex-1 truncate text-base font-semibold tracking-tight text-ink"
    >
        {title}
    </h1>

    <div class="flex shrink-0 items-center gap-2">
        <button
            type="button"
            class="hidden h-9 w-64 items-center gap-2 rounded-lg border border-white/[0.08] bg-elevated px-3 text-left text-sm text-white transition hover:border-indigo-500/40 hover:bg-card-hover focus:outline-none focus:ring-1 focus:ring-indigo-500/30 sm:flex"
            title={i18n.t.header.searchTooltip}
            onclick={onSearch}
        >
            <Search size={16} class="shrink-0 text-muted" aria-hidden="true" />
            <span class="min-w-0 flex-1 truncate text-zinc-400"
                >{i18n.t.header.searchButton}</span
            >
            <kbd
                class="shrink-0 rounded border border-white/[0.08] bg-canvas px-1.5 py-0.5 text-[10px] font-medium text-muted"
                >Ctrl K</kbd
            >
        </button>

        <button
            type="button"
            class="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/[0.08] bg-elevated text-muted transition hover:border-indigo-500/40 hover:text-ink focus:outline-none focus:ring-1 focus:ring-indigo-500/30 sm:hidden"
            aria-label={i18n.t.header.searchButton}
            onclick={onSearch}
        >
            <Search size={17} aria-hidden="true" />
        </button>

        <ActivityDropdown />

        <label class="sr-only" for="language-select"
            >{i18n.t.header.language}</label
        >
        <select
            id="language-select"
            class="h-9 rounded-lg border border-white/[0.08] bg-elevated px-2 text-xs font-semibold text-ink outline-none transition focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            value={i18n.current}
            onchange={changeLocale}
        >
            {#each locales as locale}
                <option value={locale}>{locale.toUpperCase()}</option>
            {/each}
        </select>
    </div>
</div>
