<script lang="ts">
    import { Check, LoaderCircle, Minus, Plus, Trophy } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import CircularCounter from "$shared/ui/CircularCounter.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { GameAchievementItem } from "$shared/types";

    interface Props {
        progressValue: number;
        progressLabel: string;
        progressError: unknown;
        onCounterChange: (value: number) => void;
        achievements: readonly GameAchievementItem[];
        achievementsTotal: number;
        achievementsLoading: boolean;
        achievementsBusy: boolean;
        achievementsTruncated: boolean;
        /** `.has(name)` / `.size` only; the source is a Map in the parent. */
        unlockedNames: { has(key: string): boolean; readonly size: number };
        onToggleAchievement: (name: string) => Promise<void>;
        onToggleAllAchievements: () => Promise<void>;
    }

    let {
        progressValue,
        progressLabel,
        progressError,
        onCounterChange,
        achievements,
        achievementsTotal,
        achievementsLoading,
        achievementsBusy,
        achievementsTruncated,
        unlockedNames,
        onToggleAchievement,
        onToggleAllAchievements,
    }: Props = $props();

    const allUnlocked = $derived(
        achievements.length > 0 &&
            achievements.every((ach) =>
                unlockedNames.has(ach.name.toLowerCase().trim()),
            ),
    );
</script>

<section
    class="rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06] flex flex-col items-center"
>
    <CircularCounter
        value={progressValue}
        label={progressLabel}
        onChange={onCounterChange}
    />
    {#if progressError}<p
            class="mt-2 text-center text-xs text-rose-300"
            role="alert"
        >
            {errorMessage(progressError)}
        </p>{/if}
</section>
<section
    class="space-y-3 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
>
    <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
            <Trophy size={16} class="text-amber-400" />
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {i18n.current === "ru" ? "Достижения" : "Achievements"}
            </h2>
        </div>
        <div class="flex items-center gap-2 shrink-0">
            <button
                type="button"
                class="rounded-lg border border-amber-400/30 bg-amber-400/10 px-2.5 py-1 text-[11px] font-semibold text-amber-300 transition hover:bg-amber-400/20 disabled:opacity-40 cursor-pointer"
                disabled={achievementsBusy || achievements.length === 0}
                onclick={() => void onToggleAllAchievements()}
                title={allUnlocked
                    ? i18n.current === "ru"
                        ? "Снять отметки со всех достижений"
                        : "Clear all achievements"
                    : i18n.current === "ru"
                      ? "Отметить все достижения"
                      : "Mark all achievements"}
            >
                {#if allUnlocked}
                    {i18n.current === "ru" ? "Снять все" : "Clear all"}
                {:else}
                    {i18n.current === "ru" ? "Отметить все" : "Mark all"}
                {/if}
            </button>
            <span
                class="rounded-full bg-amber-400/10 border border-amber-400/20 px-2 py-0.5 text-xs font-semibold text-amber-300"
            >
                {#if achievementsLoading}
                    <LoaderCircle
                        size={12}
                        class="animate-spin"
                        role="status"
                        aria-label={i18n.t.common.loading}
                    />
                {:else if unlockedNames.size > 0}
                    {i18n.current === "ru"
                        ? "Получено"
                        : "Unlocked"}: {unlockedNames.size} / {achievementsTotal}
                {:else}
                    {i18n.current === "ru"
                        ? "Всего достижений"
                        : "Total achievements"}: {achievementsTotal}
                {/if}
                {#if achievementsTruncated}
                    <span
                        title={i18n.current === "ru"
                            ? `Показаны первые ${achievements.length} из ${achievementsTotal}`
                            : `Showing the first ${achievements.length} of ${achievementsTotal}`}
                        >*</span
                    >
                {/if}
            </span>
        </div>
    </div>
{#if achievementsLoading}
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3 pt-1">
            {#each Array(4) as _, i (i)}
                <div class="h-14 animate-pulse rounded-lg bg-[var(--color-field)]"
                ></div>
            {/each}
        </div>
    {:else if achievements.length > 0}
        <div
            class="thin-scroll grid max-h-[520px] grid-cols-1 gap-2.5 overflow-y-auto pr-1 pt-1 sm:grid-cols-2 lg:grid-cols-3"
        >
            {#each achievements as ach (ach.name)}
                {@const isUnlocked = unlockedNames.has(
                    ach.name.toLowerCase().trim(),
                )}
                <button
                    type="button"
                    class={`flex items-center gap-3 rounded-lg border p-2.5 text-left transition cursor-pointer ${
                        isUnlocked
                            ? "border-emerald-500/40 bg-[var(--color-success-deep)] hover:border-emerald-500/60"
                            : "border-white/[0.06] bg-[var(--color-field)] hover:border-white/[0.12] opacity-75 hover:opacity-100"
                    }`}
                    onclick={() => void onToggleAchievement(ach.name)}
                    title={isUnlocked
                        ? i18n.current === "ru"
                            ? "Получено (нажмите, чтобы снять)"
                            : "Unlocked (click to lock)"
                        : i18n.current === "ru"
                          ? "Не получено (нажмите, чтобы отметить)"
                          : "Locked (click to unlock)"}
                >
                    <div class="relative h-10 w-10 flex-shrink-0">
                        {#if ach.iconUrl}
                            <img
                                src={ach.iconUrl}
                                alt={ach.name}
                                class={`h-10 w-10 rounded-md object-cover bg-black/40 border transition ${
                                    isUnlocked
                                        ? "border-emerald-400/50"
                                        : "border-white/[0.08] grayscale contrast-75"
                                }`}
                                loading="lazy"
                            />
                        {:else}
                            <div
                                class={`grid h-10 w-10 place-items-center rounded-md ${isUnlocked ? "bg-emerald-950/60 text-emerald-400" : "bg-[var(--color-panel-line)] text-amber-400"}`}
                            >
                                <Trophy size={16} />
                            </div>
                        {/if}
                        {#if isUnlocked}
                            <div
                                class="absolute -bottom-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-emerald-500 text-black shadow ring-1 ring-[var(--color-success-deep)]"
                            >
                                <Check size={10} stroke-width={3} />
                            </div>
                        {/if}
                    </div>
                    <div class="min-w-0 flex-1">
                        <p
                            class={`truncate text-xs font-semibold ${isUnlocked ? "text-emerald-300" : "text-white"}`}
                        >
                            {ach.name}
                        </p>
                        {#if ach.description}
                            <p class="line-clamp-1 text-[11px] text-muted">
                                {ach.description}
                            </p>
                        {/if}
                    </div>
                </button>
            {/each}
        </div>
    {:else}
        <!-- Achievements are external data and are fetched only on add
             or an explicit metadata refresh, never on opening the card.
             There is deliberately no fetch button here. -->
        <p class="text-xs text-muted">
            {i18n.current === "ru"
                ? "Достижения не загружены. Обновите метаданные, чтобы получить их."
                : "Achievements not loaded. Refresh metadata to fetch them."}
        </p>
    {/if}
</section>