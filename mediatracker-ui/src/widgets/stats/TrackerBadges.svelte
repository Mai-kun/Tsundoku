<script lang="ts">
    import { Crown, BookOpen, Flame, Clock, Star, Compass, Trophy } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AdvancedStats } from "$shared/types";

    interface Props {
        stats: AdvancedStats;
    }

    let { stats }: Props = $props();

    interface BadgeConfig {
        id: string;
        translationKey: keyof typeof i18n.t.stats.badges;
        icon: typeof Trophy;
        target: number;
        current: number;
    }

    const activeMediaTypesCount = $derived.by(() => {
        const hours = [
            stats.gameHours,
            stats.movieHours,
            stats.seriesHours,
            stats.animeHours,
            stats.bookHours,
            stats.mangaHours,
        ];
        return hours.filter((h) => h > 0).length;
    });

    const badges = $derived.by<BadgeConfig[]>(() => [
        {
            id: "hundred_club",
            translationKey: "hundredClub",
            icon: Crown,
            target: 100,
            current: stats.completedTitles,
        },
        {
            id: "bibliophile",
            translationKey: "bibliophile",
            icon: BookOpen,
            target: 1000,
            current: stats.totalPagesRead + stats.totalChaptersRead,
        },
        {
            id: "streak_master",
            translationKey: "streakMaster",
            icon: Flame,
            target: 7,
            current: stats.currentStreakDays,
        },
        {
            id: "time_keeper",
            translationKey: "timeKeeper",
            icon: Clock,
            target: 100,
            current: Math.floor(stats.totalHours),
        },
        {
            id: "perfectionist",
            translationKey: "perfectionist",
            icon: Star,
            target: 3,
            current: stats.scoreDistribution[10] ?? 0,
        },
        {
            id: "cultural_omnivore",
            translationKey: "omnivore",
            icon: Compass,
            target: 4,
            current: activeMediaTypesCount,
        },
    ]);

    const unlockedCount = $derived(
        badges.filter((b) => b.current >= b.target).length
    );

    const overallPercent = $derived(
        Math.round((unlockedCount / badges.length) * 100)
    );
</script>

<section class="mt-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2.5">
            <Trophy class="size-5 text-amber-400" aria-hidden="true" />
            <h2 class="text-base sm:text-lg font-semibold tracking-tight text-white">
                {i18n.t.stats.achievements}
            </h2>
        </div>
        <div class="inline-flex items-center rounded-lg border border-amber-500/20 bg-amber-500/10 px-3 py-1 text-xs font-semibold text-amber-400">
            {i18n.t.stats.unlockedCount(unlockedCount, overallPercent)}
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
        {#each badges as badge (badge.id)}
            {@const isUnlocked = badge.current >= badge.target}
            {@const progressPercent = Math.min(100, Math.round((badge.current / badge.target) * 100))}
            {@const IconComponent = badge.icon}
            <article class="bg-[#151a26] border border-white/5 rounded-xl p-4 flex flex-col justify-between transition-colors hover:border-white/10">
                <div>
                    <div class="flex items-start gap-3">
                        <div
                            class="flex size-10 shrink-0 items-center justify-center rounded-lg border transition-colors {isUnlocked
                                ? 'border-amber-500/30 bg-amber-500/10 text-amber-400'
                                : 'border-white/5 bg-white/[0.03] text-zinc-500'}"
                        >
                            <IconComponent size={20} aria-hidden="true" />
                        </div>
                        <div class="min-w-0">
                            <h3 class="text-sm font-bold text-white truncate">
                                {i18n.t.stats.badges[badge.translationKey].title}
                            </h3>
                            <p class="mt-0.5 text-xs text-muted leading-snug">
                                {i18n.t.stats.badges[badge.translationKey].description}
                            </p>
                        </div>
                    </div>
                </div>

                <div class="mt-4 pt-1">
                    {#if isUnlocked}
                        <span class="bg-amber-500/10 text-amber-400 border border-amber-500/20 text-xs px-2.5 py-1 rounded-md font-semibold self-start inline-flex items-center">
                            {i18n.t.stats.unlocked}
                        </span>
                    {:else}
                        <div class="space-y-1.5">
                            <div class="h-1.5 rounded-full bg-white/5 overflow-hidden">
                                <div
                                    class="h-full w-full origin-left rounded-full bg-purple-500 transition-transform duration-500"
                                    style="transform: scaleX({progressPercent / 100});"
                                ></div>
                            </div>
                            <div class="flex justify-between items-center text-[11px] text-muted tabular-nums">
                                <span>{i18n.t.stats.progress}</span>
                                <span>{badge.current} / {badge.target} ({progressPercent}%)</span>
                            </div>
                        </div>
                    {/if}
                </div>
            </article>
        {/each}
    </div>
</section>
