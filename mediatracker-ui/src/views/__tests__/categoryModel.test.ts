import { describe, it, expect } from "vitest";
import { MEDIA_STATUS, type MediaItem, type StatusFilter } from "$shared/types";
import {
  buildStatusGroups,
  categoryFilters,
  filterByStatus,
  type StatusSection,
} from "../categoryModel";

const sections: StatusSection[] = [
  { status: MEDIA_STATUS.inProgress, title: "In progress" },
  { status: MEDIA_STATUS.planned, title: "Planned" },
  { status: MEDIA_STATUS.completed, title: "Completed" },
  { status: MEDIA_STATUS.onHold, title: "On hold" },
  { status: MEDIA_STATUS.dropped, title: "Dropped" },
];

function item(id: string, status: number | string): MediaItem {
  return { id, title: id, status } as unknown as MediaItem;
}

describe("categoryModel", () => {
  it("groups items by status and skips empty sections when filtering by all", () => {
    const items = [
      item("a", MEDIA_STATUS.inProgress),
      item("b", String(MEDIA_STATUS.inProgress)),
      item("c", MEDIA_STATUS.completed),
    ];

    const groups = buildStatusGroups(items, "all", sections);

    expect(groups.map((group) => group.status)).toEqual([
      MEDIA_STATUS.inProgress,
      MEDIA_STATUS.completed,
    ]);
    expect(groups[0].items.map((entry) => entry.id)).toEqual(["a", "b"]);
    expect(groups[1].items.map((entry) => entry.id)).toEqual(["c"]);
  });

  it("keeps only the selected section and compares statuses numerically", () => {
    const items = [item("a", MEDIA_STATUS.completed), item("b", MEDIA_STATUS.planned)];

    const groups = buildStatusGroups(items, "2" as StatusFilter, sections);

    expect(groups).toHaveLength(1);
    expect(groups[0].status).toBe(MEDIA_STATUS.completed);
    expect(groups[0].items.map((entry) => entry.id)).toEqual(["a"]);
  });

  it("filters the flat list with numeric status comparison", () => {
    const items = [item("a", MEDIA_STATUS.completed), item("b", MEDIA_STATUS.planned)];

    expect(filterByStatus(items, "2" as StatusFilter).map((entry) => entry.id)).toEqual(["a"]);
    expect(filterByStatus(items, "all")).toHaveLength(2);
  });

  it("maps every category to the matching media query filters", () => {
    expect(categoryFilters("anime", "", "newest")).toEqual({
      search: undefined,
      sortBy: "createdAt",
      sortOrder: "desc",
      isAnime: true,
    });
    expect(categoryFilters("tvshow", "", "newest")).toEqual({
      search: undefined,
      sortBy: "createdAt",
      sortOrder: "desc",
      type: "tvshow",
      isAnime: false,
    });
    expect(categoryFilters("movie", "", "newest")).toEqual({
      search: undefined,
      sortBy: "createdAt",
      sortOrder: "desc",
      type: "movie",
      isAnime: false,
    });
    expect(categoryFilters("manga", "", "newest")).toMatchObject({ type: "manga" });
    expect(categoryFilters("game", "", "newest")).toMatchObject({ type: "game" });
    expect(categoryFilters("book", "", "newest")).toMatchObject({ type: "book" });
  });

  it("trims search and maps sort options", () => {
    expect(categoryFilters("manga", "  dune  ", "title")).toMatchObject({
      search: "dune",
      sortBy: "title",
      sortOrder: "asc",
    });
    expect(categoryFilters("manga", "  ", "oldest")).toMatchObject({
      search: undefined,
      sortBy: "createdAt",
      sortOrder: "asc",
    });
    expect(categoryFilters("manga", "", "rating")).toMatchObject({
      sortBy: "score",
      sortOrder: "desc",
    });
  });
});
