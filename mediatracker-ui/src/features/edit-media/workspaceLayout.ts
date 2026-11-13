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

/** Edges kept inside the viewport so a window can never be dragged fully out of reach. */
const EDGE_MARGIN = 96;
const TOP_BAR = 64;

export function clampWindowRect(
  rect: WorkspaceRect,
  id: WorkspaceWindowId,
  viewportW: number,
  viewportH: number,
): WorkspaceRect {
  const min = MIN_SIZES[id];
  const maxW = Math.max(viewportW - 2 * EDGE_MARGIN, min.w);
  const maxH = Math.max(viewportH - 2 * TOP_BAR, min.h);
  const w = Math.min(Math.max(rect.w, min.w), maxW);
  const h = Math.min(Math.max(rect.h, min.h), maxH);
  return {
    w,
    h,
    x: Math.min(Math.max(rect.x, EDGE_MARGIN - w), viewportW - EDGE_MARGIN),
    y: Math.min(Math.max(rect.y, TOP_BAR), viewportH - EDGE_MARGIN),
  };
}

export function clampPoint(
  point: { x: number; y: number },
  viewportW: number,
  viewportH: number,
): { x: number; y: number } {
  const { w } = COVER_SIZE;
  return {
    x: Math.min(Math.max(point.x, EDGE_MARGIN - w), viewportW - EDGE_MARGIN),
    y: Math.min(Math.max(point.y, TOP_BAR), viewportH - EDGE_MARGIN),
  };
}

/**
 * Default composition: the cover in the exact center, windows floating around it in two loose
 * columns. Values are computed from the viewport, so the arrangement scales with screen size.
 */
export function defaultLayout(viewportW: number, viewportH: number): WorkspaceLayout {
  const cx = viewportW / 2;
  const cy = viewportH / 2;
  return {
    cover: clampPoint({ x: cx - COVER_SIZE.w / 2, y: cy - COVER_SIZE.h / 2 }, viewportW, viewportH),
    windows: {
      main: clampWindowRect({ x: cx - 780, y: cy - 240, w: 480, h: 480 }, "main", viewportW, viewportH),
      alt: clampWindowRect({ x: cx - 780, y: cy + 260, w: 480, h: 260 }, "alt", viewportW, viewportH),
      notes: clampWindowRect({ x: cx + 240, y: cy - 280, w: 380, h: 260 }, "notes", viewportW, viewportH),
      quotes: clampWindowRect({ x: cx + 240, y: cy + 10, w: 380, h: 300 }, "quotes", viewportW, viewportH),
      images: clampWindowRect({ x: cx + 240, y: cy + 340, w: 380, h: 300 }, "images", viewportW, viewportH),
    },
  };
}

const STORAGE_KEY = "tsundoku.editWorkspace.layout.v1";

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
