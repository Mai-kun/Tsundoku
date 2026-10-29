import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, unmount, tick } from "svelte";
import type { MediaFilters, MediaItem } from "$shared/types";
import CategoryView from "../CategoryView.svelte";

vi.mock("$shared/api/api", () => ({
  getMedia: vi.fn(),
  deleteMedia: vi.fn(),
  getMediaItem: vi.fn(),
  setProgress: vi.fn(),
  setSeasonProgress: vi.fn(),
  errorMessage: vi.fn(() => "error"),
}));

import { getMedia } from "$shared/api/api";

const getMediaMock = vi.mocked(getMedia);

const gameItems: MediaItem[] = Array.from(
  { length: 18 },
  (_, i) =>
    ({
      id: `game-${i}`,
      title: `Game ${i}`,
      type: "game",
      status: 0,
      score: null,
      startedAt: null,
      finishedAt: null,
      coverUrl: null,
      createdAt: "2026-01-01T00:00:00Z",
      franchiseId: null,
      franchiseOrder: null,
    }) as MediaItem,
);

const mangaItems: MediaItem[] = Array.from(
  { length: 18 },
  (_, i) =>
    ({
      id: `manga-${i}`,
      title: `Manga ${i}`,
      type: "manga",
      status: 0,
      score: null,
      startedAt: null,
      finishedAt: null,
      coverUrl: null,
      createdAt: "2026-01-01T00:00:00Z",
      franchiseId: null,
      franchiseOrder: null,
    }) as MediaItem,
);

function mountView(category: string) {
  const host = document.createElement("div");
  document.body.appendChild(host);

  // The virtualizer reads its scroller from #main-scroll; give it a non-zero
  // rect so range calculation has an outer size to work with.
  const scroller = document.createElement("div");
  scroller.id = "main-scroll";
  scroller.style.height = "800px";
  document.body.appendChild(scroller);

  const instance = mount(CategoryView, {
    target: host,
    props: {
      category,
      onOpen: vi.fn(),
      onMediaChanged: vi.fn(),
    },
  });

  return {
    host,
    instance,
    destroy: () => {
      unmount(instance);
      document.body.removeChild(scroller);
      document.body.removeChild(host);
    },
  };
}

describe("CategoryView", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
  });

  it("renders items of the newly selected category after switching", async () => {
    getMediaMock.mockImplementation((filters: MediaFilters) =>
      Promise.resolve((filters.type === "manga" ? mangaItems : gameItems) as MediaItem[]),
    );

    const { host, destroy: destroyGame } = mountView("game");

    try {
      await vi.waitFor(() => expect(host.textContent).toContain("Game 0"));
      expect(host.textContent).toContain("Game 17");
      expect(host.textContent).not.toContain("Manga 0");
    } finally {
      destroyGame();
    }

    // App remounts CategoryView on every category switch ({#key activeCategory}),
    // so simulate the switch by mounting a new instance for "manga".
    const { host: mangaHost, destroy: destroyManga } = mountView("manga");

    try {
      await vi.waitFor(() => expect(mangaHost.textContent).toContain("Manga 0"));
      expect(mangaHost.textContent).toContain("Manga 17");
      expect(mangaHost.textContent).not.toContain("Game 0");
    } finally {
      destroyManga();
    }
  });
});
