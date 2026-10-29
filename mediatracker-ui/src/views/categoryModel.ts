import type { LibrarySort } from "$features/filter-and-sort/FilterBar.svelte";
import type { MediaFilters, MediaItem, MediaStatus, StatusFilter } from "$shared/types";

export type Category = "tvshow" | "movie" | "anime" | "manga" | "game" | "book";

export interface StatusSection {
  status: MediaStatus;
  title: string;
}

export interface StatusGroup extends StatusSection {
  items: MediaItem[];
}

/** Status can arrive as a number from the API or as a JSON-parsed string from localStorage. */
export function filterByStatus(items: MediaItem[], status: StatusFilter): MediaItem[] {
  return status === "all" ? items : items.filter((item) => Number(item.status) === Number(status));
}

export function buildStatusGroups(
  items: MediaItem[],
  status: StatusFilter,
  sections: readonly StatusSection[],
): StatusGroup[] {
  const buckets = new Map<number, MediaItem[]>(
    sections.map((section) => [Number(section.status), []]),
  );
  for (const item of items) {
    buckets.get(Number(item.status))?.push(item);
  }

  return sections
    .map((section) => ({
      status: section.status,
      title: section.title,
      items: buckets.get(Number(section.status)) ?? [],
    }))
    .filter((section) =>
      status === "all" ? section.items.length > 0 : Number(section.status) === Number(status),
    );
}

export function categoryFilters(
  category: Category,
  search: string,
  sort: LibrarySort,
): MediaFilters {
  const filters: MediaFilters = {
    search: search.trim() || undefined,
    ...sortFilters(sort),
  };

  switch (category) {
    case "anime":
      return { ...filters, isAnime: true };
    case "tvshow":
      return { ...filters, type: "tvshow", isAnime: false };
    case "movie":
      return { ...filters, type: "movie", isAnime: false };
    default:
      return { ...filters, type: category };
  }
}

function sortFilters(value: LibrarySort): Pick<MediaFilters, "sortBy" | "sortOrder"> {
  switch (value) {
    case "oldest":
      return { sortBy: "createdAt", sortOrder: "asc" };
    case "rating":
      return { sortBy: "score", sortOrder: "desc" };
    case "title":
      return { sortBy: "title", sortOrder: "asc" };
    default:
      return { sortBy: "createdAt", sortOrder: "desc" };
  }
}
