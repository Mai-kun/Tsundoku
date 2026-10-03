<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { GameAchievementItem, MangaVolume, MediaDetail } from "$shared/types";
    import {
        isVolumeDone,
        volumeCurrent,
        volumePercent,
        volumeProgressLabel,
        volumeTotal,
        type VolumeController,
    } from "../createVolumeController.svelte";
    import type { ProgressInfo } from "../detailTypes";
    import ProgressStepper from "../ProgressStepper.svelte";
    import GameDetailSection from "../sections/GameDetailSection.svelte";
    import MangaDetailSection from "../sections/MangaDetailSection.svelte";

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
        mangaVolumes: readonly MangaVolume[];
        volumes: VolumeController;
        onOpenVolumesTab: () => void;
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
        mangaVolumes,
        volumes,
        onOpenVolumesTab,
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

    {#if media.type === "manga"}
        <MangaDetailSection
            {media}
            volumes={mangaVolumes}
            volumeBusy={volumes.busy}
            isDone={isVolumeDone}
            current={volumeCurrent}
            total={volumeTotal}
            percent={volumePercent}
            progressLabel={volumeProgressLabel}
            onStepPage={(vol, delta) => void volumes.stepVolume(vol, delta)}
            onEdit={(vol) => volumes.openEdit(vol)}
            onDelete={(vol) => void volumes.remove(vol)}
            onMarkComplete={(vol) => void volumes.markComplete(vol)}
            onUnmarkComplete={(vol) => void volumes.unmarkComplete(vol)}
            onAddVolume={() => volumes.openAdd()}
            onGenerateVolumes={() => void volumes.generateMissing()}
            {onOpenVolumesTab}
        />
    {/if}
</div>
