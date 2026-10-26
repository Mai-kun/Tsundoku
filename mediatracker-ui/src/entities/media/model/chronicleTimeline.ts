import type { MediaItem } from "$shared/types";

// shortcut: local copy of MEDIA_STATUS to avoid runtime alias resolution in node checks
const STATUS_COMPLETED = 2;
const STATUS_IN_PROGRESS = 1;

export type TimelineScale = "months" | "years";
export type TimelineCategoryFilter =
  "all" | "game" | "anime" | "manga" | "movie" | "tvshow" | "book";

export interface ChronicleEntry {
  item: MediaItem;
  date: Date;
  dateIso: string;
  year: number;
  month: number; // 0..11
  isCompleted: boolean;
}

export interface ChronicleMonthGroup {
  month: number; // 0..11
  entries: ChronicleEntry[];
  averageScore: number | null;
}

export interface ChronicleYearGroup {
  year: number;
  months: ChronicleMonthGroup[];
  entries: ChronicleEntry[];
  totalCount: number;
  averageScore: number | null;
  topRatedItem: MediaItem | null;
}

export interface ChronicleResult {
  years: ChronicleYearGroup[];
  undatedCompleted: MediaItem[];
  totalDatedCount: number;
}

function matchesCategory(item: MediaItem, category: TimelineCategoryFilter): boolean {
  if (category === "all") return true;
  if (category === "anime") {
    return (
      (item.type === "tvshow" || item.type === "movie") &&
      Boolean((item as { isAnime?: boolean }).isAnime)
    );
  }
  if (category === "tvshow") {
    return item.type === "tvshow" && !(item as { isAnime?: boolean }).isAnime;
  }
  if (category === "movie") {
    return item.type === "movie" && !(item as { isAnime?: boolean }).isAnime;
  }
  return item.type === category;
}

function avgScore(entries: ChronicleEntry[]): number | null {
  const scored = entries.filter((e) => (e.item.score ?? 0) > 0);
  if (scored.length === 0) return null;
  const sum = scored.reduce((acc, e) => acc + (e.item.score as number), 0);
  return Math.round((sum / scored.length) * 10) / 10;
}

function topRated(entries: ChronicleEntry[]): MediaItem | null {
  const scored = entries.filter((e) => (e.item.score ?? 0) > 0);
  if (scored.length === 0) return null;
  return scored.reduce((best, e) =>
    (e.item.score as number) > (best.item.score as number) ? e : best,
  ).item;
}

export function buildChronicle(
  items: MediaItem[],
  options: { category: TimelineCategoryFilter; includeInProgress: boolean },
): ChronicleResult {
  const { category, includeInProgress } = options;

  const undatedCompleted: MediaItem[] = [];
  const dated: ChronicleEntry[] = [];

  for (const item of items) {
    if (!matchesCategory(item, category)) continue;

    const isCompleted = item.status === STATUS_COMPLETED;
    const isInProgress = item.status === STATUS_IN_PROGRESS;

    if (isCompleted) {
      const rawDate = item.finishedAt ?? item.startedAt;
      if (!rawDate) {
        undatedCompleted.push(item);
        continue;
      }
      const date = new Date(rawDate);
      dated.push({
        item,
        date,
        dateIso: rawDate,
        year: date.getFullYear(),
        month: date.getMonth(),
        isCompleted: true,
      });
    } else if (includeInProgress && isInProgress && item.startedAt) {
      const date = new Date(item.startedAt);
      dated.push({
        item,
        date,
        dateIso: item.startedAt,
        year: date.getFullYear(),
        month: date.getMonth(),
        isCompleted: false,
      });
    }
  }

  // Group by year then month
  const byYear = new Map<number, Map<number, ChronicleEntry[]>>();
  for (const entry of dated) {
    let yearMap = byYear.get(entry.year);
    if (!yearMap) {
      yearMap = new Map();
      byYear.set(entry.year, yearMap);
    }
    let monthArr = yearMap.get(entry.month);
    if (!monthArr) {
      monthArr = [];
      yearMap.set(entry.month, monthArr);
    }
    monthArr.push(entry);
  }

  // Sort entries within each month newest → oldest
  const sortEntries = (arr: ChronicleEntry[]) =>
    arr.sort((a, b) => b.date.getTime() - a.date.getTime());

  const years: ChronicleYearGroup[] = [];
  const sortedYears = [...byYear.keys()].sort((a, b) => b - a);

  for (const year of sortedYears) {
    const yearMap = byYear.get(year)!;
    const sortedMonths = [...yearMap.keys()].sort((a, b) => b - a);

    const monthGroups: ChronicleMonthGroup[] = sortedMonths.map((month) => {
      const entries = sortEntries(yearMap.get(month)!);
      return { month, entries, averageScore: avgScore(entries) };
    });

    const allEntries = monthGroups.flatMap((m) => m.entries);
    years.push({
      year,
      months: monthGroups,
      entries: allEntries,
      totalCount: allEntries.length,
      averageScore: avgScore(allEntries),
      topRatedItem: topRated(allEntries),
    });
  }

  return { years, undatedCompleted, totalDatedCount: dated.length };
}
