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
</script>

<div class="space-y-6">
    <QuickFactsSection {media} />
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
    <NotesSection notes={media.notes} {onEdit} />
    <CastSection media={media} />
    {#if creator}
        <CreatorSection
            creatorName={creator.name}
            role={creator.role}
            currentMediaId={media.id}
            {onOpenMedia}
            {onSearch}
        />
    {/if}
</div>
