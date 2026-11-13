/**
 * Window geometry for the spatial edit workspace. Everything is viewport-anchored: a saved layout
 * from a bigger screen is clamped back into view instead of leaving windows stranded off-screen.
 */

export type WorkspaceWindowId = "main" | "alt" | "notes" | "quotes" | "images";

export interface WorkspaceRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface WorkspaceLayout {
  cover: { x: number; y: number };
  windows: Record<WorkspaceWindowId, WorkspaceRect>;
}

export const WORKSPACE_WINDOW_IDS: WorkspaceWindowId[] = [
  "main",
  "alt",
  "notes",
  "quotes",
  "images",
];

/** Central poster node: fixed size, position is draggable and persisted. */
export const COVER_SIZE = { w: 220, h: 330 };

const MIN_SIZES: Record<WorkspaceWindowId, { w: number; h: number }> = {
  main: { w: 380, h: 320 },
  alt: { w: 280, h: 180 },
  notes: { w: 280, h: 180 },
  quotes: { w: 300, h: 200 },
  images: { w: 300, h: 240 },
};

export function minWindowSize(id: WorkspaceWindowId): { w: number; h: number } {
  return MIN_SIZES[id];
}

/** Hard viewport bounds: 16px side/bottom margin, 64px reserved for the floating toolbar. */
const SIDE_MARGIN = 16;
const TOP_BAR = 64;
const BOTTOM_MARGIN = 16;

export function clampWindowRect(
  rect: WorkspaceRect,
  id: WorkspaceWindowId,
  viewportW: number,
  viewportH: number,
): WorkspaceRect {
  const min = MIN_SIZES[id];
  // Size first: never wider/taller than the visible band between the hard margins.
  const w = Math.min(Math.max(rect.w, min.w), Math.max(viewportW - 2 * SIDE_MARGIN, min.w));
  const h = Math.min(
    Math.max(rect.h, min.h),
    Math.max(viewportH - TOP_BAR - BOTTOM_MARGIN, min.h),
  );
  // Then position: the whole rect must stay inside the band, even if that shrinks it below min.
  return {
    w,
    h,
    x: Math.min(Math.max(rect.x, SIDE_MARGIN), Math.max(viewportW - SIDE_MARGIN - w, SIDE_MARGIN)),
    y: Math.min(
      Math.max(rect.y, TOP_BAR),
      Math.max(viewportH - BOTTOM_MARGIN - h, TOP_BAR),
    ),
  };
}

export function clampPoint(
  point: { x: number; y: number },
  viewportW: number,
  viewportH: number,
): { x: number; y: number } {
  const { w, h } = COVER_SIZE;
  return {
    x: Math.min(Math.max(point.x, SIDE_MARGIN), Math.max(viewportW - SIDE_MARGIN - w, SIDE_MARGIN)),
    y: Math.min(Math.max(point.y, TOP_BAR), Math.max(viewportH - BOTTOM_MARGIN - h, TOP_BAR)),
  };
}

/**
 * Default composition, matching the target mockup: two windows per side column with the
 * alternative-titles window above the cover in the middle. Coordinates adapt to the viewport, so
 * every node fits on screen without overlaps at any reasonable window size.
 */
export function defaultLayout(viewportW: number, viewportH: number): WorkspaceLayout {
  const cx = viewportW / 2;
  const bandTop = TOP_BAR + 20;
  const bandBottom = viewportH - BOTTOM_MARGIN;
  const bandH = bandBottom - bandTop;

  // Three columns: side columns flank the central one (alt titles + cover) without touching it.
  const centerW = Math.min(470, Math.max(360, viewportW * 0.29));
  const centerLeft = cx - centerW / 2;
  const centerRight = cx + centerW / 2;
  const sideW = Math.min(
    520,
    Math.max(
      MIN_SIZES.main.w,
      centerLeft - 40 - 24,
      viewportW - SIDE_MARGIN - (centerRight + 40),
    ),
  );
  const leftX = 24;
  const rightX = centerRight + 40;

  // Left column: basics (taller) over quotes; right column: notes over images.
  const mainH = Math.floor(bandH * 0.58);
  const quotesH = bandH - mainH - 16;
  const notesH = Math.floor(bandH * 0.38);
  const imagesH = bandH - notesH - 16;

  // Central column: alt titles right under the toolbar, the cover floating below it.
  const altH = Math.min(260, bandH - COVER_SIZE.h - 60);

  return {
    cover: clampPoint({ x: cx - COVER_SIZE.w / 2, y: bandTop + altH + 40 }, viewportW, viewportH),
    windows: {
      main: clampWindowRect({ x: leftX, y: bandTop, w: sideW, h: mainH }, "main", viewportW, viewportH),
      quotes: clampWindowRect(
        { x: leftX, y: bandTop + mainH + 16, w: sideW, h: quotesH },
        "quotes",
        viewportW,
        viewportH,
      ),
      alt: clampWindowRect(
        { x: centerLeft, y: bandTop, w: centerW, h: altH },
        "alt",
        viewportW,
        viewportH,
      ),
      notes: clampWindowRect({ x: rightX, y: bandTop, w: sideW, h: notesH }, "notes", viewportW, viewportH),
      images: clampWindowRect(
        { x: rightX, y: bandTop + notesH + 16, w: sideW, h: imagesH },
        "images",
        viewportW,
        viewportH,
      ),
    },
  };
}

// v2: the target composition (basics+quotes left, alt titles+cover center, notes+images right).
// Bumping the key makes the new scheme apply for everyone on the next open.
const STORAGE_KEY = "tsundoku.editWorkspace.layout.v2";

export function loadLayout(viewportW: number, viewportH: number): WorkspaceLayout {
  const layout = defaultLayout(viewportW, viewportH);
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return layout;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) return layout;
    const saved = parsed as {
      cover?: { x?: number; y?: number };
      windows?: Record<string, Partial<WorkspaceRect>>;
    };
    const cover = saved.cover;
    if (typeof cover?.x === "number" && typeof cover?.y === "number") {
      layout.cover = clampPoint({ x: cover.x, y: cover.y }, viewportW, viewportH);
    }
    for (const id of WORKSPACE_WINDOW_IDS) {
      const rect = saved.windows?.[id];
      if (!rect) continue;
      const merged: WorkspaceRect = {
        x: typeof rect.x === "number" ? rect.x : layout.windows[id].x,
        y: typeof rect.y === "number" ? rect.y : layout.windows[id].y,
        w: typeof rect.w === "number" ? rect.w : layout.windows[id].w,
        h: typeof rect.h === "number" ? rect.h : layout.windows[id].h,
      };
      layout.windows[id] = clampWindowRect(merged, id, viewportW, viewportH);
    }
    return layout;
  } catch {
    return layout;
  }
}

export function saveLayout(layout: WorkspaceLayout): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
  } catch {
    // Private mode / full quota: the layout just is not remembered, nothing to escalate.
  }
}
