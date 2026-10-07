<script lang="ts">
    import { Check, ChevronLeft, ChevronRight, LoaderCircle, Trophy, X } from "$shared/ui/Icons.svelte";
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

    const pageSize = 60;
    let searchQuery = $state("");
    let currentPage = $state(1);
    let sectionElement: HTMLElement | null = $state(null);

    const filteredAchievements = $derived(
        searchQuery.trim() === ""
            ? achievements
            : achievements.filter((ach) => {
                  const q = searchQuery.toLowerCase().trim();
                  return (
                      ach.name.toLowerCase().includes(q) ||
                      Boolean(ach.description?.toLowerCase().includes(q))
                  );
              }),
    );

    const totalPages = $derived(
        Math.max(1, Math.ceil(filteredAchievements.length / pageSize)),
    );

    const pagedAchievements = $derived(
        filteredAchievements.slice(
            (currentPage - 1) * pageSize,
            currentPage * pageSize,
        ),
    );

    $effect(() => {
        void achievements.length;
        searchQuery;
        currentPage = 1;
    });

    $effect(() => {
        if (currentPage > totalPages) {
            currentPage = totalPages;
        }
    });

    function goToPage(page: number) {
        if (page < 1 || page > totalPages || page === currentPage) return;
        currentPage = page;
        sectionElement?.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    const paginationPages = $derived.by((): (number | "...")[] => {
        if (totalPages <= 7) {
            return Array.from({ length: totalPages }, (_, i) => i + 1);
        }

        if (currentPage <= 4) {
            return [1, 2, 3, 4, 5, "...", totalPages];
        }

        if (currentPage >= totalPages - 3) {
            return [
                1,
                "...",
                totalPages - 4,
                totalPages - 3,
                totalPages - 2,
                totalPages - 1,
                totalPages,
            ];
        }

        return [
            1,
            "...",
            currentPage - 1,
            currentPage,
            currentPage + 1,
            "...",
            totalPages,
        ];
    });
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
    bind:this={sectionElement}
    class="space-y-3 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
>
    <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
            <Trophy size={16} class="text-amber-400" />
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {i18n.current === "ru" ? "Достижения" : "Achievements"}
            </h2>
        </div>
        <div class="flex flex-wrap items-center gap-2">
            {#if achievements.length > 0}
                <div class="relative flex items-center">
                    <input
                        type="text"
                        bind:value={searchQuery}
                        placeholder={i18n.current === "ru"
                            ? "Поиск достижений по названию и описанию..."
                            : "Search achievements by name and description..."}
                        class="w-56 sm:w-64 bg-[#161a24] border border-white/10 rounded-md px-3 py-1.5 pr-7 text-xs text-white placeholder-zinc-500 focus:border-[#5844e0] outline-none transition"
                    />
                    {#if searchQuery}
                        <button
                            type="button"
                            onclick={() => (searchQuery = "")}
                            class="absolute right-2 text-zinc-400 hover:text-white transition cursor-pointer"
                            title={i18n.current === "ru" ? "Очистить" : "Clear"}
                        >
                            <X size={14} />
                        </button>
                    {/if}
                </div>
            {/if}
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
        {#if filteredAchievements.length === 0}
            <p class="py-4 text-center text-xs text-muted">
                {i18n.current === "ru"
                    ? "Достижения не найдены"
                    : "No achievements found"}
            </p>
        {:else}
            <div
                class="thin-scroll grid max-h-[520px] grid-cols-1 gap-2.5 overflow-y-auto pr-1 pt-1 sm:grid-cols-2 lg:grid-cols-3"
            >
                {#each pagedAchievements as ach (ach.name)}
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

            {#if totalPages > 1}
                <div class="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-white/[0.06]">
                    <span class="text-xs text-muted">
                        {i18n.current === "ru"
                            ? `Страница ${currentPage} из ${totalPages} (показано ${pagedAchievements.length} из ${filteredAchievements.length} достижений)`
                            : `Page ${currentPage} of ${totalPages} (showing ${pagedAchievements.length} of ${filteredAchievements.length} achievements)`}
                    </span>

                    <div class="flex items-center gap-1.5">
                        <button
                            type="button"
                            disabled={currentPage === 1}
                            onclick={() => goToPage(currentPage - 1)}
                            class="h-9 w-24 shrink-0 flex items-center justify-center gap-1 text-xs rounded-md border border-white/10 font-medium text-slate-300 transition hover:bg-white/10 hover:text-white bg-transparent disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent cursor-pointer"
                        >
                            <ChevronLeft size={14} />
                            <span>{i18n.current === "ru" ? "Назад" : "Prev"}</span>
                        </button>

                        {#each paginationPages as p, i (i)}
                            {#if p === "..."}
                                <span
                                    class="w-9 h-9 shrink-0 flex items-center justify-center rounded-md text-xs tabular-nums text-muted"
                                    >...</span
                                >
                            {:else}
                                <button
                                    type="button"
                                    onclick={() => goToPage(p)}
                                    class={`w-9 h-9 shrink-0 flex items-center justify-center rounded-md text-xs tabular-nums transition cursor-pointer ${
                                        currentPage === p
                                            ? "bg-[#5844e0] text-white font-medium"
                                            : "border border-white/10 text-slate-300 hover:bg-white/10 hover:text-white"
                                    }`}
                                >
                                    {p}
                                </button>
                            {/if}
                        {/each}

                        <button
                            type="button"
                            disabled={currentPage === totalPages}
                            onclick={() => goToPage(currentPage + 1)}
                            class="h-9 w-24 shrink-0 flex items-center justify-center gap-1 text-xs rounded-md border border-white/10 font-medium text-slate-300 transition hover:bg-white/10 hover:text-white bg-transparent disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent cursor-pointer"
                        >
                            <span>{i18n.current === "ru" ? "Вперед" : "Next"}</span>
                            <ChevronRight size={14} />
                        </button>
                    </div>
                </div>
            {/if}
        {/if}
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
