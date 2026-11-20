import type { MediaItem } from "$shared/types";
import {
  apiFetch,
  invalidateSourcesCache,
} from "$shared/api/api";
import {
  Bookmark,
  BookOpen,
  Clapperboard,
  Gamepad2,
  Library,
  Sparkles,
  Tv,
} from "$shared/ui/Icons";

/**
 * Вынесенная категория навигации («Комиксы», «Ранобэ») — виртуальный раздел сайдбара,
 * вынесенный из родительского типа медиа. Пока категория активна, её элементы не показываются
 * внутри родителя: фильтрация происходит на сервере (SQL), а на Главной — этим же матчером.
 * Серверная часть: Features/Settings/NavigationCategories.
 */
export interface PromotedSubcategory {
  /** Slug в навигации: "comics", "light-novels". */
  id: string;
  label: string;
  icon: string;
  /** Канонический MediaType сервера: "Book", "Manga", "Game", "TvShow", "Movie". */
  parentType: string;
  /** "format" | "genre" | "tag". */
  matchKind: string;
  matchValue: string;
}

let categories = $state.raw<PromotedSubcategory[]>([]);
let loaded = false;
let loadPromise: Promise<void> | null = null;

/** Реактивный список активных категорий (порядок = порядок в сайдбаре). */
export function promotedCategories(): PromotedSubcategory[] {
  return categories;
}

export function promotedCategoryById(id: string): PromotedSubcategory | null {
  return categories.find((c) => c.id === id) ?? null;
}

/** Родительский MediaType в нижнем регистре — как его ждут MediaFilters ("book"). */
export function promotedParentType(sub: PromotedSubcategory): string {
  return sub.parentType.toLowerCase();
}

export async function loadNavigationCategories(force = false): Promise<PromotedSubcategory[]> {
  if (loaded && !force) return categories;
  if (!loadPromise || force) {
    loadPromise = (async () => {
      const response = await apiFetch("/api/settings/navigation-categories");
      if (!response.ok) throw new Error(`navigation-categories: ${response.status}`);
      categories = (await response.json()) as PromotedSubcategory[];
      loaded = true;
    })();
  }
  await loadPromise;
  return categories;
}

export async function saveNavigationCategories(
  list: PromotedSubcategory[],
): Promise<PromotedSubcategory[]> {
  const response = await apiFetch("/api/settings/navigation-categories", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ categories: list }),
  });
  if (!response.ok) {
    const detail = (await response.json().catch(() => null)) as { detail?: string } | null;
    throw new Error(detail?.detail ?? `navigation-categories: ${response.status}`);
  }
  categories = (await response.json()) as PromotedSubcategory[];
  loaded = true;
  // Активные категории меняют состав «Книг» и других родителей — серверные кэши списков
  // на клиенте сбрасываются, вьюхи пересобирают выборки через свой $effect на promotedCategories.
  invalidateSourcesCache();
  return categories;
}

const asList = (value: string[] | string | null | undefined): string[] => {
  if (!value) return [];
  if (Array.isArray(value)) return value;
  return value.split(",").map((v) => v.trim());
};

function normalizeListValue(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, "");
}

/** Клиентский матчер — тот же контракт, что и SQL-фрагмент PromotedSubcategorySql. */
export function matchesSubcategory(item: MediaItem, sub: PromotedSubcategory): boolean {
  if (item.type !== promotedParentType(sub)) return false;

  switch (sub.matchKind) {
    case "format":
      return (item.format ?? "").toLowerCase() === sub.matchValue.trim().toLowerCase();
    case "genre": {
      const needle = normalizeListValue(sub.matchValue);
      return asList(item.genres).some((g) => normalizeListValue(g) === needle);
    }
    case "tag": {
      const needle = normalizeListValue(sub.matchValue);
      return asList(item.tags).some((t) => normalizeListValue(t) === needle);
    }
    default:
      return false;
  }
}

/** Вынесенная категория, в которую попадает элемент (первая совпавшая), или null. */
export function promotedCategoryOfItem(item: MediaItem): PromotedSubcategory | null {
  for (const sub of categories) {
    if (matchesSubcategory(item, sub)) return sub;
  }
  return null;
}

/** Согласованный набор иконок для вынесенных категорий (имя из конфига → компонент). */
const ICONS: Record<string, typeof Bookmark> = {
  bookmark: Bookmark,
  "book-open": BookOpen,
  clapperboard: Clapperboard,
  gamepad: Gamepad2,
  library: Library,
  sparkle: Sparkles,
  tv: Tv,
};

export function promotedIcon(name: string): typeof Bookmark {
  return ICONS[name] ?? Bookmark;
}

/** Готовые пресеты для быстрых кнопок в настройках. */
export const PROMOTED_PRESETS: readonly PromotedSubcategory[] = [
  {
    id: "comics",
    label: "Комиксы",
    icon: "bookmark",
    parentType: "Book",
    matchKind: "format",
    matchValue: "comics",
  },
  {
    id: "light-novels",
    label: "Ранобэ",
    icon: "sparkle",
    parentType: "Book",
    matchKind: "format",
    matchValue: "light_novel",
  },
];
