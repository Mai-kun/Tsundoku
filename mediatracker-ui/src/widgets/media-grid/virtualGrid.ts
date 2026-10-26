/**
 * Viewport -> column mapping for the card grid. Must mirror the Tailwind
 * responsive classes (grid-cols-2 sm:grid-cols-3 lg:grid-cols-4
 * xl:grid-cols-5 2xl:grid-cols-7): breakpoints are viewport-based, not
 * container-based, so row chunking and the rendered grid always agree.
 */
export function columnsForWidth(viewportWidth: number): number {
  if (viewportWidth < 640) return 2;
  if (viewportWidth < 1024) return 3;
  if (viewportWidth < 1280) return 4;
  if (viewportWidth < 1536) return 5;
  return 7;
}

// Seed values for the fixed per-breakpoint row height (poster 3:4 + title block
// + controls). Rows are uniform within a breakpoint but grow with card width,
// so the constant differs per column count (measured 329px @2 cols ... 442px
// pitch @3 cols @768px viewport). MediaGrid replaces the seed with one exact
// measurement of the first rendered row per breakpoint.
export function estimateRowHeight(viewportWidth: number): number {
  if (viewportWidth < 640) return 329;
  if (viewportWidth < 1024) return 400;
  if (viewportWidth < 1280) return 345;
  if (viewportWidth < 1536) return 385;
  return 410;
}

/**
 * Splits a flat item list into rows of `columns` items for row-based
 * virtualization. Preserves order; the last row holds the remainder.
 */
export function chunkIntoRows<T>(items: readonly T[], columns: number): T[][] {
  const rows: T[][] = [];
  for (let i = 0; i < items.length; i += columns) {
    rows.push(items.slice(i, i + columns));
  }
  return rows;
}
