<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { GameAchievementItem, MediaDetail } from "$shared/types";
    import type { ProgressInfo } from "../detailTypes";
    import ProgressStepper from "../ProgressStepper.svelte";
    import GameDetailSection from "../sections/GameDetailSection.svelte";
    import CreatorSection from "../sections/CreatorSection.svelte";
    import NotesSection from "../sections/NotesSection.svelte";
    import QuickFactsSection from "../sections/QuickFactsSection.svelte";
    import CastSection from "../sections/CastSection.svelte";
    import TrailerSection from "../sections/TrailerSection.svelte";
    import type { CreatorRole, MediaItem } from "$shared/types";

    interface Props {
        media: MediaDetail;
        /** Null when the type tracks no counter (e.g. a movie already watched). */
        support: ProgressInfo | null;
        progressValue: number;
        progressPercent: number;
        progressError: unknown;
        onStep: (delta: number) => void;
        /** Game counter; the parent owns the debounced write. */
        onCounterChange: (value: number) => void;
        achievements: readonly GameAchievementItem[];
        achievementsTotal: number;
        achievementsLoading: boolean;
        achievementsBusy: boolean;
        achievementsTruncated: boolean;
        unlockedAchievementNames: Map<string, string>;
        onToggleAchievement: (name: string) => Promise<void>;
        onToggleAllAchievements: () => Promise<void>;
        onOpenMedia: (item: MediaItem) => void;
        onSearch: (query: string) => void;
        onEdit: () => void;
    }

    let {
        media,
        support,
        progressValue,
        progressPercent,
        progressError,
        onStep,
        onCounterChange,
        achievements,
        achievementsTotal,
        achievementsLoading,
        achievementsBusy,
        achievementsTruncated,
        unlockedAchievementNames,
        onToggleAchievement,
        onToggleAllAchievements,
        onOpenMedia,
        onSearch,
        onEdit,
    }: Props = $props();

    const creator = $derived.by((): { name: string; role: CreatorRole } | null => {
        if (media.type === "movie") {
            if (media.director?.trim()) return { name: media.director.trim(), role: "director" };
            if (media.studio?.trim()) return { name: media.studio.trim(), role: "studio" };
        } else if (media.type === "book" || media.type === "manga") {
            if (media.author?.trim()) return { name: media.author.trim(), role: "author" };
        } else if (media.type === "tvshow") {
            const name = media.studio?.trim() || media.network?.trim();
            if (name) return { name, role: "studio" };
        }
        return null;
    });

    const statusLabel = $derived.by(() => {
        switch (media.status) {
            case 0: return i18n.t.status.planned;
            case 1: return i18n.t.status.inProgress;
            case 2: return i18n.t.status.completed;
            case 3: return i18n.t.status.paused;
            default: return i18n.t.status.dropped;
        }
    });
</script>

<div class="space-y-5">
    <QuickFactsSection {media} />

    <div class="grid grid-cols-1 items-stretch gap-5 lg:grid-cols-2">
        <div class="flex flex-col">
            {#if media.type === "game"}
                <GameDetailSection
                    {progressValue}
                    progressLabel={support?.label ?? i18n.t.detail.hoursLabel}
                    {progressError}
                    {onCounterChange}
                    {achievements}
                    {achievementsTotal}
                    {achievementsLoading}
                    {achievementsBusy}
                    {achievementsTruncated}
                    unlockedNames={unlockedAchievementNames}
                    {onToggleAchievement}
                    {onToggleAllAchievements}
                />
            {:else if support && support.editable}
                <ProgressStepper
                    progress={support}
                    value={progressValue}
                    percent={progressPercent}
                    error={progressError}
                    {onStep}
                />
            {:else}
                <div class="flex h-full min-h-[190px] flex-col justify-center rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5">
                    <span class="text-xs font-bold uppercase tracking-wider text-muted">{i18n.t.status.label}</span>
                    <span class="mt-1 text-lg font-bold text-white">{statusLabel}</span>
                </div>
            {/if}
        </div>

        <div class="flex flex-col">
            {#if creator}
                <CreatorSection
                    creatorName={creator.name}
                    role={creator.role}
                    currentMediaId={media.id}
                    {onOpenMedia}
                    {onSearch}
                />
            {:else}
                <div class="flex h-full min-h-[190px] items-center rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 text-sm text-muted">
                    {i18n.t.creator.noCreator}
                </div>
            {/if}
        </div>

        <div class="flex flex-col">
            <TrailerSection trailerVideoId={media.trailerVideoId ?? null} title={media.title} />
        </div>

        <div class="flex flex-col">
            <NotesSection notes={media.notes} {onEdit} />
        </div>
    </div>

    <CastSection media={media} />
</div>
