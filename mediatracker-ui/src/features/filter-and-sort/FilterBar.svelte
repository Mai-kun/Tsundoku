<script module lang="ts">
  import {
    ArrowDown,
    ArrowUp,
    LayoutGrid,
    ListChecks,
    Star,
    Tag,
    Type,
    Search,
    SlidersHorizontal,
  } from "$shared/ui/Icons.svelte";

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
  import { i18n } from "$shared/i18n/index.svelte";
  import { ChevronDown } from "$shared/ui/Icons.svelte";
  import { MEDIA_STATUS, type MediaStatus, type StatusFilter } from "$shared/types";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";

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

  function handleSearch(event: Event) {
    onSearchChange((event.currentTarget as HTMLInputElement).value);
  }

  /* The status select carries the status id as the option value, the label in the trigger. */
  function handleStatus(value: string) {
    onStatusChange(value === "all" ? "all" : (Number(value) as MediaStatus));
  }

  const statusOptions = $derived<{ value: string; label: string }[]>(
    statuses.map((option) => ({
      value: option === "all" ? "all" : String(option),
      label: labelForStatus(option),
    })),
  );

  const statusValue = $derived(status === "all" ? "all" : String(status));

  const sortOptions = $derived<{ value: LibrarySort; label: string }[]>([
    { value: "newest", label: i18n.t.sort.newest },
    { value: "oldest", label: i18n.t.sort.oldest },
    { value: "rating", label: i18n.t.sort.rating },
    { value: "title", label: i18n.t.sort.title },
  ]);

  const groupOptions = $derived<{ value: GroupBy; label: string }[]>([
    { value: "status", label: i18n.t.grouping.byStatus },
    { value: "franchise", label: i18n.t.grouping.byFranchise },
    { value: "all", label: i18n.t.grouping.all },
  ]);
</script>

<section
  class="bg-surface space-y-3 rounded-lg p-3 sm:p-4"
  aria-label={i18n.t.library.filtersLabel}
>
  <div class="flex flex-col gap-3 lg:flex-row lg:items-center">
    <div class="flex min-w-0 flex-1 items-center gap-2">
      <SlidersHorizontal size={16} class="text-muted shrink-0" aria-hidden="true" />
      <PopoverMenu
        id="library-group"
        options={groupOptions}
        selected={groupBy}
        onSelect={(value) => onGroupByChange(value as GroupBy)}
        label={i18n.t.grouping.label}
        placement="bottom-start"
        openOnHover
        closeDelay={220}
      >
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          {@const GroupIcon = GROUP_ICONS[groupBy]}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            class="tap bg-field text-muted hover:text-ink grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-white/10 transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
            title={i18n.t.grouping.label}
            aria-label={i18n.t.grouping.label}
          >
            <GroupIcon size={18} stroke-width={2} aria-hidden="true" />
          </button>
        {/snippet}
        {#snippet renderOption({ option })}
          {@const GroupIcon = GROUP_ICONS[option.value as GroupBy]}
          <span class="flex items-center gap-2">
            <GroupIcon size={16} stroke-width={2} aria-hidden="true" />
            <span class="truncate">{option.label}</span>
          </span>
        {/snippet}
      </PopoverMenu>

      <label class="sr-only" for="library-status">{i18n.t.status.label}</label>
      <PopoverMenu
        id="library-status"
        options={statusOptions}
        selected={statusValue}
        onSelect={(value) => handleStatus(value as string)}
        label={i18n.t.status.label}
        placement="bottom-start"
        openOnHover
        closeDelay={220}
      >
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            class="tap bg-field text-ink flex h-10 shrink-0 items-center gap-2 rounded-lg border border-white/10 px-3 text-xs font-semibold transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
            title={i18n.t.status.label}
          >
            <span class="truncate">{labelForStatus(status)}</span>
            {#if counts[status] !== undefined}
              <span
                class="bg-card text-muted rounded-full px-2 py-0.5 text-[10px] font-bold"
                aria-live="polite">{counts[status]}</span
              >
            {/if}
            <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
          </button>
        {/snippet}
      </PopoverMenu>
    </div>

    <div class="flex items-center gap-2">
      <label class="relative min-w-0 flex-1 lg:w-52 lg:flex-none">
        <span class="sr-only">{i18n.t.header.searchButton}</span>
        <Search
          size={18}
          class="text-muted pointer-events-none absolute top-1/2 left-3 -translate-y-1/2"
          aria-hidden="true"
        />
        <input
          class="bg-field text-ink placeholder:text-muted h-10 w-full rounded-lg border border-white/10 pr-2.5 pl-9 text-sm outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
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
        {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
          {@const SortIcon = SORT_ICONS[sort]}
          <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
            class="tap bg-field text-muted hover:text-ink grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-white/10 transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
            title={i18n.t.sort.label}
            aria-label={i18n.t.sort.label}
          >
            <SortIcon size={18} stroke-width={2} aria-hidden="true" />
          </button>
        {/snippet}
        {#snippet renderOption({ option })}
          {@const SortIcon = SORT_ICONS[option.value as LibrarySort]}
          <span class="flex items-center gap-2">
            <SortIcon size={16} stroke-width={2} aria-hidden="true" />
            <span class="truncate">{option.label}</span>
          </span>
        {/snippet}
      </PopoverMenu>
    </div>
  </div>
</section>
