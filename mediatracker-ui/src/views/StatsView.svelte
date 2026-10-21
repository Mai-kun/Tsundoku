<script lang="ts">
    import { BarChart3, RefreshCw, Sparkles } from "$shared/ui/Icons.svelte";
    import { errorMessage, getAdvancedStats, getTasteProfile } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AdvancedStats, TasteProfile } from "$shared/types";
    import StatsHeroBanner from "$widgets/stats/StatsHeroBanner.svelte";
    import TimeDistributionDonut from "$widgets/stats/TimeDistributionDonut.svelte";
    import RatingPsychology from "$widgets/stats/RatingPsychology.svelte";
    import MonthlyActivityChart from "$widgets/stats/MonthlyActivityChart.svelte";
    import TopGenresBar from "$widgets/stats/TopGenresBar.svelte";
    import BacklogHealth from "$widgets/stats/BacklogHealth.svelte";
    import TrackerBadges from "$widgets/stats/TrackerBadges.svelte";
    import ActivityHeatmap from "$widgets/stats/ActivityHeatmap.svelte";
    import TastePersonaCard from "$widgets/stats/taste-profile/TastePersonaCard.svelte";
    import GenreRadarChart from "$widgets/stats/taste-profile/GenreRadarChart.svelte";
    import CriticalDivergenceCard from "$widgets/stats/taste-profile/CriticalDivergenceCard.svelte";
    import SunkCostCard from "$widgets/stats/taste-profile/SunkCostCard.svelte";
    import DropAnalyticsCard from "$widgets/stats/taste-profile/DropAnalyticsCard.svelte";
    import GenreParadoxCard from "$widgets/stats/taste-profile/GenreParadoxCard.svelte";
    import EraAffinityCard from "$widgets/stats/taste-profile/EraAffinityCard.svelte";

    interface Props {
        refreshKey: number;
        onOpenMedia?: (mediaId: string) => void;
    }

    let { refreshKey, onOpenMedia }: Props = $props();

    type StatsTab = "summary" | "taste";

    let activeTab = $state<StatsTab>("summary");
    let stats = $state<AdvancedStats | null>(null);
    let profile = $state<TasteProfile | null>(null);
    let loading = $state(true);
    let loadError = $state<unknown>(null);
    let profileError = $state<unknown>(null);
    let requestSequence = 0;

    $effect(() => {
        void refreshKey;
        void loadStats(++requestSequence);
    });

    async function loadStats(sequence: number) {
        loading = true;
        loadError = null;
        profileError = null;

        try {
            const [nextStats, nextProfile] = await Promise.allSettled([getAdvancedStats(), getTasteProfile()]);
            if (sequence !== requestSequence) {
                return;
            }

            if (nextStats.status === "fulfilled") {
                stats = nextStats.value;
            } else {
                stats = null;
                loadError = nextStats.reason;
            }

            if (nextProfile.status === "fulfilled") {
                profile = nextProfile.value;
            } else {
                profile = null;
                profileError = nextProfile.reason;
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
    <div class="flex justify-center">
        <div class="grid w-full max-w-md grid-cols-2 gap-1 rounded-xl bg-white/[0.03] p-1" role="tablist" aria-label={i18n.t.stats.title}>
            <button
                type="button"
                role="tab"
                aria-selected={activeTab === "summary"}
                class="flex h-9 items-center justify-center gap-2 rounded-lg px-3 text-sm font-medium transition-colors duration-200 {activeTab ===
                'summary'
                    ? 'bg-[#5844e0]/30 text-white'
                    : 'text-slate-400 hover:text-white'}"
                onclick={() => (activeTab = "summary")}
            >
                <BarChart3 class="size-4" aria-hidden="true" />
                {i18n.t.stats.tabSummary}
            </button>
            <button
                type="button"
                role="tab"
                aria-selected={activeTab === "taste"}
                class="flex h-9 items-center justify-center gap-2 rounded-lg px-3 text-sm font-medium transition-colors duration-200 {activeTab ===
                'taste'
                    ? 'bg-[#5844e0]/30 text-white'
                    : 'text-slate-400 hover:text-white'}"
                onclick={() => (activeTab = "taste")}
            >
                <Sparkles class="size-4" aria-hidden="true" />
                {i18n.t.stats.tabTaste}
            </button>
        </div>
    </div>

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
    {:else if activeTab === "summary" && stats}
        <StatsHeroBanner {stats} />

        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
            <div class="bg-[#151a26] border border-white/5 rounded-xl p-5 lg:col-span-7 flex flex-col justify-center">
                <TimeDistributionDonut {stats} />
            </div>

            <div class="bg-[#151a26] border border-white/5 rounded-xl p-5 lg:col-span-5">
                <RatingPsychology {stats} />
            </div>
        </div>

        <div class="grid grid-cols-1 gap-6 mt-6">
            <MonthlyActivityChart completions={stats.monthlyCompletions} />
            <ActivityHeatmap dailyActivity={stats.dailyActivity ?? {}} />
            <TopGenresBar genres={stats.topGenres} genresByType={stats.topGenresByType ?? {}} />
        </div>

        <BacklogHealth {stats} onMediaChanged={() => loadStats(++requestSequence)} />
        <TrackerBadges {stats} />
    {:else if activeTab === "taste"}
        {#if profileError}
            <div
                class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-xl border border-rose-500/10 bg-rose-500/5 p-6 text-center"
            >
                <p class="text-sm text-rose-300" role="alert">
                    {errorMessage(profileError)}
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
        {:else if profile}
            <TastePersonaCard persona={profile.persona} />

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <GenreRadarChart axes={profile.genreRadar} />
                <EraAffinityCard eras={profile.eraAffinity} />
            </div>

            <SunkCostCard sunkCost={profile.sunkCost} />

            {#if profile.dropAnalytics}
                <DropAnalyticsCard analytics={profile.dropAnalytics} />
            {/if}

            <CriticalDivergenceCard divergence={profile.divergence} {onOpenMedia} />

            <GenreParadoxCard paradox={profile.genreParadox} />
        {/if}
    {/if}
</div>
