/**
 * Viewport -> column mapping for the card grid. Mirrors the Tailwind ladder up
 * to 2xl, then caps at 6 columns so desktop cards stay enlarged (~190-220px).
 * estimateRowHeight stays derived from the actual column width, so the
 * virtualizer pitch always matches the rendered card height at any viewport.
 */
export function columnsForWidth(viewportWidth: number): number {
  if (viewportWidth < 640) return 2;
  if (viewportWidth < 1024) return 3;
  if (viewportWidth < 1280) return 4;
  if (viewportWidth < 1536) return 5;
  return 6; // 6 cards per row on 2xl / desktop (enlarged card width ~190-220px)
}

// Seed value for the fixed per-breakpoint row height (poster 3:4 + title block
// + controls). The seed is derived from the actual column width at this
// viewport — including the dynamic ultra-wide range — so the virtualizer never
// spaces rows tighter than the real rendered card height. MediaGrid replaces
// the seed with one exact measurement of the first rendered row.
export function estimateRowHeight(viewportWidth: number): number {
  const cols = columnsForWidth(viewportWidth);
  const sidebarWidth = viewportWidth >= 1024 ? 240 : 0;
  const availableWidth = Math.max(300, viewportWidth - sidebarWidth - 64);
  const gapTotal = (cols - 1) * 16;
  const cardWidth = Math.max(120, (availableWidth - gapTotal) / cols);
  const posterHeight = cardWidth * 1.5; // 2:3 poster ratio
  const infoHeight = 90; // title, subtitle, stepper padding
  return Math.round(posterHeight + infoHeight);
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
