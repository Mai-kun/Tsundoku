import type { LibrarySort } from "$features/filter-and-sort/FilterBar.svelte";
import type { PromotedSubcategory } from "$shared/api/navigationCategories.svelte";
import type { MediaFilters, MediaItem, MediaStatus, StatusFilter } from "$shared/types";

/** Базовые категории. Вынесенные (промоутед) подкатегории — динамические id из настроек. */
export const BASE_CATEGORIES = ["tvshow", "movie", "anime", "manga", "game", "book"] as const;

export type BaseCategory = (typeof BASE_CATEGORIES)[number];

/** Категория может быть вынесенной подкатегорией (произвольный slug из конфигурации). */
export type Category = BaseCategory | (string & {});

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
  // Plain record with explicit 0-safe keys: MEDIA_STATUS.planned is 0, and any
  // `if (buckets[key])` shortcut or Map-less lookup must not treat it as missing.
  const buckets: Record<number, MediaItem[]> = {};
  for (const section of sections) {
    buckets[Number(section.status)] = [];
  }
  for (const item of items) {
    const s = Number(item.status);
    if (buckets[s]) {
      buckets[s].push(item);
    }
  }

  return sections
    .map((section) => ({
      status: section.status,
      title: section.title,
      items: buckets[Number(section.status)] ?? [],
    }))
    .filter((section) =>
      status === "all" ? section.items.length > 0 : Number(section.status) === Number(status),
    );
}

export function categoryFilters(
  category: Category,
  search: string,
  sort: LibrarySort,
  promoted: readonly PromotedSubcategory[] = [],
): MediaFilters {
  const filters: MediaFilters = {
    search: search.trim() || undefined,
    ...sortFilters(sort),
  };

  // Вынесенная подкатегория: запрос идёт по родительскому типу с subId — сервер сам
  // применяет match-условие и исключает элементы из родительской категории.
  const promotedCategory = promoted.find((c) => c.id === category);
  if (promotedCategory) {
    return {
      ...filters,
      type: promotedCategory.parentType.toLowerCase() as MediaFilters["type"],
      subId: promotedCategory.id,
    };
  }

  switch (category) {
    case "anime":
      return { ...filters, isAnime: true };
    case "tvshow":
      return { ...filters, type: "tvshow", isAnime: false };
    case "movie":
      return { ...filters, type: "movie", isAnime: false };
    default:
      // Не вынесенная и не спец-категория: категория совпадает с типом медиа.
      return { ...filters, type: category as MediaFilters["type"] };
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
