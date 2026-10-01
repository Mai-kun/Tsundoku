<script lang="ts">
    import Search from "lucide-svelte/icons/search";
    import SlidersHorizontal from "lucide-svelte/icons/sliders-horizontal";
    import { i18n } from "$lib/i18n/index.svelte";
    import {
        MEDIA_STATUS,
        type MediaStatus,
        type StatusFilter,
    } from "$lib/types";

    export type LibrarySort = "newest" | "oldest" | "rating" | "title";
    export type GroupBy = "status" | "franchise" | "all";

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

    function handleGroup(event: Event) {
        onGroupByChange(
            (event.currentTarget as HTMLSelectElement).value as GroupBy,
        );
    }

    function handleSort(event: Event) {
        onSortChange(
            (event.currentTarget as HTMLSelectElement).value as LibrarySort,
        );
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
            <label class="sr-only" for="library-group"
                >{i18n.t.grouping.label}</label
            >
            <select
                id="library-group"
                class="shrink-0 whitespace-nowrap rounded-md border border-white/10 bg-field px-3 py-1.5 text-xs font-semibold text-ink outline-none focus:ring-2 focus:ring-accent/40"
                value={groupBy}
                onchange={handleGroup}
            >
                <option value="status">{i18n.t.grouping.byStatus}</option>
                <option value="franchise">{i18n.t.grouping.byFranchise}</option>
                <option value="all">{i18n.t.grouping.all}</option>
            </select>

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
            <label class="sr-only" for="library-sort">{i18n.t.sort.label}</label
            >
            <select
                id="library-sort"
                class="h-8 rounded-md border border-white/10 bg-field px-2 text-xs font-medium text-ink outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
                value={sort}
                onchange={handleSort}
            >
                <option value="newest">{i18n.t.sort.newest}</option>
                <option value="oldest">{i18n.t.sort.oldest}</option>
                <option value="rating">{i18n.t.sort.rating}</option>
                <option value="title">{i18n.t.sort.title}</option>
            </select>
        </div>
    </div>
</section>
