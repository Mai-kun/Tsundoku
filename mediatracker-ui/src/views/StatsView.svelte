<script lang="ts">
    import { BookOpen, Bookmark, CheckCircle2, Clock3, Film, Gamepad2, Library, RefreshCw, Tv } from "$shared/ui/Icons.svelte";
    import { errorMessage, getStats } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaStats } from "$shared/types";

    interface Props {
        refreshKey: number;
    }

    let { refreshKey }: Props = $props();

    let stats = $state<MediaStats | null>(null);
    let loading = $state(true);
    let loadError = $state<unknown>(null);
    let requestSequence = 0;

    $effect(() => {
        void refreshKey;
        void loadStats(++requestSequence);
    });

    async function loadStats(sequence: number) {
        loading = true;
        loadError = null;

        try {
            const nextStats = await getStats();
            if (sequence === requestSequence) {
                stats = nextStats;
            }
        } catch (error) {
            if (sequence === requestSequence) {
                loadError = error;
            }
        } finally {
            if (sequence === requestSequence) {
                loading = false;
            }
        }
    }

    function retry() {
        void loadStats(++requestSequence);
    }

    function format(value: number): string {
        return new Intl.NumberFormat(i18n.current).format(value);
    }
</script>

{#snippet metric(
    value: number,
    label: string,
    Icon: typeof Library,
    tone: string,
)}
    <article
        class="rounded-lg border border-white/[0.06] bg-card p-5 transition hover:border-white/[0.08]"
    >
        <div class="flex items-center gap-2">
            <Icon size={16} class={tone} aria-hidden="true" />
            <p class="truncate text-xs font-medium text-muted">{label}</p>
        </div>
        <p class="mt-3 text-2xl font-bold tabular-nums text-ink">
            {format(value)}
        </p>
    </article>
{/snippet}

<div class="mx-auto max-w-6xl space-y-6">
    <div>
        <p
            class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
        >
            {i18n.t.library.collectionLabel}
        </p>
        <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">
            {i18n.t.stats.title}
        </h2>
    </div>

    {#if loading}
        <div class="grid grid-cols-2 gap-4 md:grid-cols-4" aria-hidden="true">
            {#each Array(8) as _, index (index)}
                <div
                    class="h-28 animate-pulse rounded-lg border border-white/[0.06] bg-card"
                ></div>
            {/each}
        </div>
        <p class="sr-only" role="status">{i18n.t.common.loading}</p>
    {:else if loadError}
        <div
            class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
        >
            <p class="text-sm text-rose-200" role="alert">
                {errorMessage(loadError)}
            </p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover"
                onclick={retry}
                ><RefreshCw size={15} aria-hidden="true" />{i18n.t.common
                    .retry}</button
            >
        </div>
    {:else if stats}
        <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
            {@render metric(
                stats.totalItems,
                i18n.t.stats.totalItems,
                Library,
                "text-accent-soft",
            )}
            {@render metric(
                stats.completedItems,
                i18n.t.stats.completedItems,
                CheckCircle2,
                "text-emerald-400",
            )}
            {@render metric(
                stats.inProgressItems,
                i18n.t.stats.inProgressItems,
                Clock3,
                "text-[#a5b4fc]",
            )}
            {@render metric(
                stats.plannedItems,
                i18n.t.stats.plannedItems,
                Bookmark,
                "text-zinc-300",
            )}
            {@render metric(
                stats.totalHoursPlayed,
                i18n.t.stats.hours,
                Gamepad2,
                "text-sky-400",
            )}
            {@render metric(
                stats.totalPagesRead,
                i18n.t.stats.pages,
                BookOpen,
                "text-amber-300",
            )}
            {@render metric(
                stats.totalChaptersRead,
                i18n.t.stats.chapters,
                BookOpen,
                "text-amber-300",
            )}
            {@render metric(
                stats.totalEpisodesWatched,
                i18n.t.stats.episodes,
                Tv,
                "text-violet-300",
            )}
            {@render metric(
                stats.completedGamesCount,
                i18n.t.stats.gamesCompleted,
                Gamepad2,
                "text-sky-400",
            )}
            {@render metric(
                stats.completedBooksCount,
                i18n.t.stats.booksCompleted,
                BookOpen,
                "text-amber-300",
            )}
            {@render metric(
                stats.completedMoviesCount,
                i18n.t.stats.moviesCompleted,
                Film,
                "text-accent-soft",
            )}
        </div>
    {/if}
</div>
