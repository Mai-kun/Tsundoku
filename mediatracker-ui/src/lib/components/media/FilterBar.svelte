<script module lang="ts">
    import ArrowDown from "lucide-svelte/icons/arrow-down";
    import ArrowUp from "lucide-svelte/icons/arrow-up";
    import LayoutGrid from "lucide-svelte/icons/layout-grid";
    import ListChecks from "lucide-svelte/icons/list-checks";
    import Star from "lucide-svelte/icons/star";
    import Tag from "lucide-svelte/icons/tag";
    import Type from "lucide-svelte/icons/type";

    export type LibrarySort = "newest" | "oldest" | "rating" | "title";
    export type GroupBy = "status" | "franchise" | "all";

    /* The sort/group controls are icon-only, so every option keeps its label for
       aria/title — the words just stop taking pixels in the bar itself. */
    export const SORT_ICONS = {
        newest: ArrowDown,
        oldest: ArrowUp,
        rating: Star,
        title: Type,
    } as const;

    export const GROUP_ICONS = {
        status: ListChecks,
        franchise: Tag,
        all: LayoutGrid,
    } as const;
</script>

<script lang="ts">
    import Search from "lucide-svelte/icons/search";
    import SlidersHorizontal from "lucide-svelte/icons/sliders-horizontal";
    import { i18n } from "$lib/i18n/index.svelte";
    import {
        MEDIA_STATUS,
        type MediaStatus,
        type StatusFilter,
    } from "$lib/types";
    import PopoverMenu from "$lib/components/ui/PopoverMenu.svelte";

    interface Props {
        status: StatusFilter;
        sort: LibrarySort;
        groupBy?: GroupBy;
        search: string;
        counts?: Partial<Record<StatusFilter, number>>;
        onStatusChange: (status: StatusFilter) => void;
        onSortChange: (sort: LibrarySort) => void;
        onGroupByChange?: (groupBy: GroupBy) => void;
        onSearchChange: (query: string) => void;
    }

    let {
        status,
        sort,
        groupBy = "status",
        search,
        counts = {},
        onStatusChange,
        onSortChange,
        onGroupByChange = () => {},
        onSearchChange,
    }: Props = $props();

    const statuses: StatusFilter[] = [
        "all",
        MEDIA_STATUS.planned,
        MEDIA_STATUS.inProgress,
        MEDIA_STATUS.completed,
        MEDIA_STATUS.onHold,
        MEDIA_STATUS.dropped,
    ];

    function labelForStatus(value: StatusFilter): string {
        switch (value) {
            case "all":
                return i18n.t.status.all;
            case MEDIA_STATUS.planned:
                return i18n.t.status.planned;
            case MEDIA_STATUS.inProgress:
                return i18n.t.status.inProgress;
            case MEDIA_STATUS.completed:
                return i18n.t.status.completed;
            case MEDIA_STATUS.onHold:
                return i18n.t.status.paused;
            case MEDIA_STATUS.dropped:
                return i18n.t.status.dropped;
        }
    }

    function handleStatus(event: Event) {
        const value = (event.currentTarget as HTMLSelectElement).value;
        onStatusChange(
            value === "all" ? "all" : (Number(value) as MediaStatus),
        );
    }

    function handleSearch(event: Event) {
        onSearchChange((event.currentTarget as HTMLInputElement).value);
    }

    const sortOptions = $derived<
        { value: LibrarySort; label: string }[]
    >([
        { value: "newest", label: i18n.t.sort.newest },
        { value: "oldest", label: i18n.t.sort.oldest },
        { value: "rating", label: i18n.t.sort.rating },
        { value: "title", label: i18n.t.sort.title },
    ]);

    const groupOptions = $derived<
        { value: GroupBy; label: string }[]
    >([
        { value: "status", label: i18n.t.grouping.byStatus },
        { value: "franchise", label: i18n.t.grouping.byFranchise },
        { value: "all", label: i18n.t.grouping.all },
    ]);
</script>

<section
    class="space-y-3 rounded-lg bg-surface p-3 sm:p-4"
    aria-label={i18n.t.library.filtersLabel}
>
    <div class="flex flex-col gap-3 lg:flex-row lg:items-center">
        <div class="flex min-w-0 flex-1 items-center gap-2">
            <SlidersHorizontal
                size={16}
                class="shrink-0 text-muted"
                aria-hidden="true"
            />
            <PopoverMenu
                id="library-group"
                options={groupOptions}
                selected={groupBy}
                onSelect={(value) => onGroupByChange(value as GroupBy)}
                label={i18n.t.grouping.label}
                placement="bottom-start"
            >
                {#snippet trigger({ popoverTargetId, anchorName })}
                    {@const GroupIcon = GROUP_ICONS[groupBy]}
                    <button
                        type="button"
                        popovertarget={popoverTargetId}
                        popovertargetaction="toggle"
                        style="anchor-name: {anchorName}"
                        class="tap grid h-12 w-12 shrink-0 place-items-center rounded-lg border border-white/10 bg-field text-muted transition hover:border-white/20 hover:text-ink has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                        title={i18n.t.grouping.label}
                        aria-label={i18n.t.grouping.label}
                    >
                        <GroupIcon size={22} stroke-width={2} aria-hidden="true" />
                    </button>
                {/snippet}
                {#snippet renderOption({ option })}
                    {@const GroupIcon = GROUP_ICONS[option.value as GroupBy]}
                    <span class="flex items-center gap-2">
                        <GroupIcon
                            size={16}
                            stroke-width={2}
                            aria-hidden="true"
                        />
                        <span class="truncate">{option.label}</span>
                    </span>
                {/snippet}
            </PopoverMenu>

            <label class="sr-only" for="library-status"
                >{i18n.t.status.label}</label
            >
            <select
                id="library-status"
                class="rounded-md border border-white/10 bg-field px-3 py-1.5 text-xs text-ink outline-none focus:ring-2 focus:ring-accent/40"
                value={status === "all" ? "all" : String(status)}
                onchange={handleStatus}
            >
                {#each statuses as option (option)}
                    <option value={option === "all" ? "all" : String(option)}
                        >{labelForStatus(option)}</option
                    >
                {/each}
            </select>
            {#if counts[status] !== undefined}
                <span
                    class="rounded-full bg-card px-2.5 py-1 text-xs font-semibold text-ink"
                    aria-live="polite">{counts[status]}</span
                >
            {/if}
        </div>

        <div class="flex gap-2">
            <label class="relative min-w-0 flex-1 lg:w-52 lg:flex-none">
                <span class="sr-only">{i18n.t.header.searchButton}</span>
                <Search
                    size={15}
                    class="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted"
                    aria-hidden="true"
                />
                <input
                    class="h-8 w-full rounded-md border border-white/10 bg-field pl-8 pr-2.5 text-xs text-ink outline-none placeholder:text-muted focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                    value={search}
                    placeholder={i18n.t.header.searchButton}
                    oninput={handleSearch}
                />
            </label>
            <PopoverMenu
                id="library-sort"
                options={sortOptions}
                selected={sort}
                onSelect={(value) => onSortChange(value as LibrarySort)}
                label={i18n.t.sort.label}
                placement="bottom-end"
                openOnHover
                closeDelay={220}
            >
                {#snippet trigger({ popoverTargetId, anchorName })}
                    {@const SortIcon = SORT_ICONS[sort]}
                    <button
                        type="button"
                        popovertarget={popoverTargetId}
                        popovertargetaction="toggle"
                        style="anchor-name: {anchorName}"
                        class="tap grid h-12 w-12 shrink-0 place-items-center rounded-lg border border-white/10 bg-field text-muted transition hover:border-white/20 hover:text-ink has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                        title={i18n.t.sort.label}
                        aria-label={i18n.t.sort.label}
                    >
                        <SortIcon size={22} stroke-width={2} aria-hidden="true" />
                    </button>
                {/snippet}
                {#snippet renderOption({ option })}
                    {@const SortIcon = SORT_ICONS[option.value as LibrarySort]}
                    <span class="flex items-center gap-2">
                        <SortIcon
                            size={16}
                            stroke-width={2}
                            aria-hidden="true"
                        />
                        <span class="truncate">{option.label}</span>
                    </span>
                {/snippet}
            </PopoverMenu>
        </div>
    </div>
</section>
