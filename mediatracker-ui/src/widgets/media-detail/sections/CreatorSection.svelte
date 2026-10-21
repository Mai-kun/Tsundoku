<script lang="ts">
    import { getCreatorSummary } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { CreatorRole, MediaItem, StaffMember } from "$shared/types";
    import { BookOpen, Clapperboard, Gamepad2, Search } from "$shared/ui/Icons.svelte";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import PeopleSizeToggle from "./PeopleSizeToggle.svelte";

    interface Props {
        creatorName: string;
        role: CreatorRole;
        mediaType?: string;
        /** Overrides the role's default caption (network, mangaka, developer). */
        label?: string | null;
        currentMediaId: string;
        imageUrl?: string | null;
        /** Key crew parsed from the stored staff snapshot; renders even without a studio. */
        staff?: readonly StaffMember[];
        /** Media category key (anime counts as its own one) for the per-category staff card size. */
        category: string;
        onOpenMedia: (item: MediaItem) => void;
        onSearch: (query: string) => void;
    }

    let {
        creatorName,
        role,
        mediaType,
        label = null,
        currentMediaId,
        imageUrl = null,
        staff = [],
        category,
        onOpenMedia,
        onSearch,
    }: Props = $props();

    let summary = $state<Awaited<ReturnType<typeof getCreatorSummary>>>(null);
    let loading = $state(true);

    $effect(() => {
        const name = creatorName;
        const currentId = currentMediaId;
        const currentRole = role;
        let active = true;
        if (!name) {
            // No studio/author on the row: the card still renders, but only the staff grid.
            loading = false;
            summary = null;
            return;
        }
        loading = true;
        void getCreatorSummary(name, currentRole, currentId)
            .then((value) => {
                if (active) summary = value;
            })
            .catch(() => {
                if (active) summary = null;
            })
            .finally(() => {
                if (active) loading = false;
            });
        return () => {
            active = false;
        };
    });

    const isRu = $derived(i18n.current === "ru");
    const largeStaff = $derived(uiSettings.getStaffSize(category) === "large");

    const completionPercent = $derived(
        summary && summary.totalCount > 0
            ? Math.round((summary.completedCount / summary.totalCount) * 100)
            : 0,
    );

    const displayLabel = $derived.by(() => {
        if (label) return label.toUpperCase();
        if (mediaType === "game") return isRu ? "РАЗРАБОТЧИК" : "DEVELOPER";
        if (role === "studio") return isRu ? "СТУДИЯ" : "STUDIO";
        if (role === "director") return isRu ? "РЕЖИССЁР" : "DIRECTOR";
        return isRu ? "АВТОР" : "AUTHOR";
    });

    function getCreatorIcon() {
        if (mediaType === "game" || (label && /разработчик|developer/i.test(label))) return Gamepad2;
        if (mediaType === "book" || mediaType === "manga" || role === "author") return BookOpen;
        return Clapperboard;
    }

    function statusLabel(status: MediaItem["status"]): string {
        switch (status) {
            case 0: return i18n.t.status.planned;
            case 1: return i18n.t.status.inProgress;
            case 2: return i18n.t.status.completed;
            case 3: return i18n.t.status.paused;
            default: return i18n.t.status.dropped;
        }
    }
</script>

<section class="space-y-3.5 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm">
    <!-- 1. Шапка карточки ("Визитка Создателя") -->
    {#if creatorName}
        <div class="flex items-center justify-between gap-3">
            <!-- Слева: стильный квадрат size-10 + мелкий лейбл + крупное имя -->
            <div class="flex min-w-0 items-center gap-3">
                {#if imageUrl}
                    <img
                        src={imageUrl}
                        alt={creatorName}
                        loading="lazy"
                        referrerpolicy="no-referrer"
                        class="size-10 shrink-0 rounded-xl bg-accent/15 border border-accent/30 object-cover"
                    />
                {:else}
                    {@const IconComponent = getCreatorIcon()}
                    <div class="size-10 shrink-0 rounded-xl bg-accent/15 border border-accent/30 text-accent-soft grid place-items-center">
                        <IconComponent size={20} aria-hidden="true" />
                    </div>
                {/if}
                <div class="min-w-0">
                    <p class="text-[10px] font-bold uppercase tracking-wider text-muted truncate">
                        {displayLabel}
                    </p>
                    <h2 class="truncate text-base font-extrabold text-white" title={creatorName}>
                        {creatorName}
                    </h2>
                </div>
            </div>

            <!-- Справа: золотистый бейдж ★ 9.0 и компактная кнопка поиска Search -->
            <div class="flex items-center gap-2 shrink-0">
                {#if summary?.averageScore !== null && summary?.averageScore !== undefined}
                    <div
                        class="inline-flex items-center gap-1 rounded-lg border border-amber-400/30 bg-amber-400/10 px-2.5 py-1 text-xs font-black text-amber-300 select-none"
                        title={isRu ? `Средняя оценка: ${summary.averageScore.toFixed(1)}` : `Average score: ${summary.averageScore.toFixed(1)}`}
                    >
                        ★ {summary.averageScore.toFixed(1)}
                    </div>
                {/if}
                <button
                    type="button"
                    class="tap size-8 grid place-items-center rounded-lg border border-white/10 bg-white/[0.04] text-muted hover:border-accent/40 hover:bg-accent/10 hover:text-accent-soft transition cursor-pointer"
                    onclick={() => onSearch(creatorName)}
                    title={isRu ? "Искать другие работы в базе" : "Search other works"}
                    aria-label={isRu ? "Искать другие работы в базе" : "Search other works"}
                >
                    <Search size={15} />
                </button>
            </div>
        </div>
    {/if}

    <!-- 2. Компактная строка освоения в коллекции -->
    {#if summary}
        <div class="rounded-lg bg-white/[0.03] p-2.5 border border-white/5 space-y-2">
            <div class="text-xs text-muted flex items-center justify-between">
                <span>
                    {isRu ? "В вашей коллекции" : "In your library"}: <strong class="text-white font-semibold">{summary.totalCount}</strong> • {isRu ? "Завершено" : "Completed"}: <strong class="text-white font-semibold">{summary.completedCount}</strong> ({completionPercent}%)
                </span>
            </div>
            <div class="h-1.5 w-full overflow-hidden rounded-full bg-[var(--color-field)] border border-white/[0.04]">
                <div
                    class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#818cf8] transition-all duration-300"
                    style="width: {Math.min(100, Math.max(0, completionPercent))}%"
                ></div>
            </div>
        </div>
    {:else if loading}
        <div class="h-10 w-full animate-pulse rounded-lg bg-white/[0.03]"></div>
    {/if}

    <!-- 2.5 Команда создателей: директор, сценарист, художник... -->
    {#if staff.length > 0}
        <div class="grid grid-cols-1 gap-2.5 border-t border-white/[0.06] sm:grid-cols-2 pt-3">
            <div class="flex items-center justify-between gap-2 sm:col-span-2">
                <h3 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                    {i18n.t.creator.staffHeading}
                </h3>
                <PeopleSizeToggle {category} block="staff" />
            </div>
            {#each staff as person, idx (person.name + idx)}
                <div class="flex {largeStaff ? 'gap-3' : 'min-w-0 items-center gap-2.5'}">
                    {#if person.imageUrl}
                        <img
                            src={person.imageUrl}
                            alt={person.name}
                            loading="lazy"
                            referrerpolicy="no-referrer"
                            class="{largeStaff
                                ? 'w-16 h-20 rounded-xl shadow-md'
                                : 'size-10 rounded-lg'} shrink-0 bg-white/5 object-cover ring-1 ring-white/10"
                        />
                    {:else}
                        <span
                            class="{largeStaff
                                ? 'w-16 h-20 shrink-0 rounded-xl'
                                : 'size-10 shrink-0 rounded-lg'} grid place-items-center bg-white/5 text-[11px] font-bold text-muted ring-1 ring-white/10"
                            aria-hidden="true"
                        >
                            {person.name.slice(0, 1).toUpperCase()}
                        </span>
                    {/if}
                    <div class="min-w-0">
                        <p
                            class="{largeStaff
                                ? 'text-sm leading-snug line-clamp-2'
                                : 'truncate text-xs'} font-bold text-white"
                            title={person.name}
                        >
                            {person.name}
                        </p>
                        {#if person.role}
                            <p
                                class="{largeStaff
                                    ? 'text-xs mt-1'
                                    : 'truncate text-[11px]'} text-muted {largeStaff ? 'line-clamp-2' : ''}"
                                title={person.role}
                            >
                                {person.role}
                            </p>
                        {/if}
                    </div>
                </div>
            {/each}
        </div>
    {/if}

    <!-- 3. Галерея других работ (только если otherItems.length > 0) -->
    {#if summary && summary.otherItems && summary.otherItems.length > 0}
        <div class="space-y-2 pt-1">
            <h3 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {i18n.t.creator.otherWorks}
            </h3>
            <div class="flex gap-3 overflow-x-auto pb-2 thin-scroll">
                {#each summary.otherItems as item (item.id)}
                    <button
                        type="button"
                        class="group w-24 shrink-0 text-left sm:w-28 cursor-pointer"
                        onclick={() => onOpenMedia(item)}
                        aria-label={`${item.title}, ${statusLabel(item.status)}`}
                    >
                        <div class="relative aspect-[2/3] overflow-hidden rounded-lg bg-black/20 border border-white/[0.06] group-hover:border-accent/40 transition">
                            {#if item.coverUrl}
                                <img
                                    src={item.coverUrl}
                                    alt=""
                                    loading="lazy"
                                    referrerpolicy="no-referrer"
                                    class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
                                />
                            {:else}
                                <div class="grid h-full place-items-center px-2 text-center text-xs text-muted">
                                    {item.title}
                                </div>
                            {/if}
                        </div>
                        <span class="mt-1.5 block truncate text-xs font-medium text-white group-hover:text-accent-soft transition">
                            {item.title}
                        </span>
                        <span class="flex items-center justify-between gap-1 text-[11px] text-muted">
                            <span class="truncate">{statusLabel(item.status)}</span>
                            {#if item.score !== null}
                                <span class="shrink-0 text-amber-300 font-bold">★ {item.score}</span>
                            {/if}
                        </span>
                    </button>
                {/each}
            </div>
        </div>
    {/if}
</section>
