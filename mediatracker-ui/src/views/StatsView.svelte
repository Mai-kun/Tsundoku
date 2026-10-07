<script lang="ts">
    import { RefreshCw } from "$shared/ui/Icons.svelte";
    import { errorMessage, getAdvancedStats } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AdvancedStats } from "$shared/types";
    import StatsHeroBanner from "$widgets/stats/StatsHeroBanner.svelte";
    import TimeDistributionDonut from "$widgets/stats/TimeDistributionDonut.svelte";
    import RatingPsychology from "$widgets/stats/RatingPsychology.svelte";
    import MonthlyActivityChart from "$widgets/stats/MonthlyActivityChart.svelte";
    import TopGenresBar from "$widgets/stats/TopGenresBar.svelte";
    import BacklogHealth from "$widgets/stats/BacklogHealth.svelte";
    import TrackerBadges from "$widgets/stats/TrackerBadges.svelte";

    interface Props {
        refreshKey: number;
    }

    let { refreshKey }: Props = $props();

    let stats = $state<AdvancedStats | null>(null);
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
            const nextStats = await getAdvancedStats();
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
</script>

<div class="mx-auto max-w-6xl space-y-6">
    {#if loading}
        <div class="space-y-4" aria-hidden="true">
            <div class="space-y-2">
                <div class="h-8 w-72 max-w-full animate-pulse rounded-lg bg-white/5"></div>
                <div class="h-4 w-96 max-w-full animate-pulse rounded-lg bg-white/5"></div>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
                {#each Array(3) as _, index (index)}
                    <div class="h-20 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
                {/each}
            </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6" aria-hidden="true">
            <div class="h-64 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
            <div class="h-64 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
        </div>

        <div class="grid grid-cols-1 gap-6" aria-hidden="true">
            <div class="h-64 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
            <div class="h-40 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
        </div>

        <!-- Skeleton for BacklogHealth and TrackerBadges -->
        <div class="space-y-6" aria-hidden="true">
            <div class="h-36 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
            <div class="space-y-4">
                <div class="flex items-center justify-between">
                    <div class="h-6 w-48 animate-pulse rounded-lg bg-white/5"></div>
                    <div class="h-6 w-36 animate-pulse rounded-lg bg-white/5"></div>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    {#each Array(6) as _, index (index)}
                        <div class="h-32 animate-pulse rounded-xl border border-white/5 bg-[#151a26]"></div>
                    {/each}
                </div>
            </div>
        </div>
        <p class="sr-only" role="status">{i18n.t.common.loading}</p>
    {:else if loadError}
        <div
            class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-xl border border-rose-500/10 bg-rose-500/5 p-6 text-center"
        >
            <p class="text-sm text-rose-300" role="alert">
                {errorMessage(loadError)}
            </p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-lg bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover"
                onclick={retry}
            >
                <RefreshCw size={15} aria-hidden="true" />
                {i18n.t.common.retry}
            </button>
        </div>
    {:else if stats}
        <StatsHeroBanner {stats} />

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div class="bg-[#151a26] border border-white/5 rounded-xl p-5">
                <TimeDistributionDonut {stats} />
            </div>

            <div class="bg-[#151a26] border border-white/5 rounded-xl p-5">
                <RatingPsychology {stats} />
            </div>
        </div>

        <div class="grid grid-cols-1 gap-6 mt-6">
            <MonthlyActivityChart completions={stats.monthlyCompletions} />
            <TopGenresBar genres={stats.topGenres} />
        </div>

        <BacklogHealth {stats} />
        <TrackerBadges {stats} />
    {/if}
</div>