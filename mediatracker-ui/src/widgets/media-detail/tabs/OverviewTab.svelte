<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { GameAchievementItem, MediaDetail } from "$shared/types";
    import type { ProgressInfo } from "../detailTypes";
    import ProgressStepper from "../ProgressStepper.svelte";
    import GameDetailSection from "../sections/GameDetailSection.svelte";

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
    }: Props = $props();
</script>

<div class="space-y-6">
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
    {/if}
</div>
