import { describe, it, expect } from "vitest";
import { chunkIntoRows, columnsForWidth, estimateRowHeight } from "../virtualGrid";

describe("virtualGrid", () => {
  it("matches Tailwind responsive breakpoints with a 6-column desktop cap", () => {
    expect(columnsForWidth(0)).toBe(2);
    expect(columnsForWidth(639)).toBe(2);
    expect(columnsForWidth(640)).toBe(3);
    expect(columnsForWidth(1023)).toBe(3);
    expect(columnsForWidth(1024)).toBe(4);
    expect(columnsForWidth(1279)).toBe(4);
    expect(columnsForWidth(1280)).toBe(5);
    expect(columnsForWidth(1535)).toBe(5);
    // 2xl / desktop / ultra-wide: enlarged cards, 6 per row.
    expect(columnsForWidth(1536)).toBe(6);
    expect(columnsForWidth(1920)).toBe(6);
    expect(columnsForWidth(2560)).toBe(6);
    expect(columnsForWidth(20000)).toBe(6);
  });

  it("chunks array into rows properly including remainder and empty lists", () => {
    expect(chunkIntoRows([1, 2, 3, 4, 5, 6, 7], 7)).toEqual([[1, 2, 3, 4, 5, 6, 7]]);
    expect(chunkIntoRows([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], 7)).toEqual([
      [1, 2, 3, 4, 5, 6, 7],
      [8, 9, 10, 11, 12, 13, 14],
    ]);
    expect(chunkIntoRows([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], 7)).toEqual([
      [1, 2, 3, 4, 5, 6, 7],
      [8, 9, 10, 11, 12, 13],
    ]);
    expect(chunkIntoRows([1, 2, 3], 7)).toEqual([[1, 2, 3]]);
    expect(chunkIntoRows([], 7)).toEqual([]);
  });

  it("preserves item order and count across all column configurations", () => {
    const items = Array.from({ length: 100 }, (_, i) => i);
    for (const columns of [2, 3, 4, 5, 6]) {
      const rows = chunkIntoRows(items, columns);
      const flat = rows.flat();
      expect(flat.length).toBe(items.length);
      expect(flat).toEqual(items);
      for (let i = 0; i < rows.length - 1; i++) {
        expect(rows[i].length).toBe(columns);
      }
    }
  });

  it("derives row height from the actual column width at each viewport", () => {
    // Formula: round(cardWidth * 1.5), the card is a pure 2:3 poster.
    const expected = (viewportWidth: number) => {
      const cols = columnsForWidth(viewportWidth);
      const sidebarWidth = viewportWidth >= 1024 ? 240 : 0;
      const availableWidth = Math.max(300, viewportWidth - sidebarWidth - 64);
      const gapTotal = (cols - 1) * 16;
      const cardWidth = Math.max(120, (availableWidth - gapTotal) / cols);
      return Math.round(cardWidth * 1.5);
    };
    for (const width of [0, 639, 640, 1023, 1024, 1279, 1280, 1535, 1536, 1919, 2560, 20000]) {
      expect(estimateRowHeight(width)).toBe(expected(width));
    }
    // Sanity: heights stay plausible for real posters (2:3 ratio only).
    expect(estimateRowHeight(0)).toBeGreaterThanOrEqual(200);
    expect(estimateRowHeight(0)).toBeLessThanOrEqual(350);
    // The estimate tracks the rendered card width: at 2560px with 6 columns
    // the card spans (2560 - 240 - 64 - 5*16) / 6 px and the row grows with it.
    expect(estimateRowHeight(2560)).toBe(Math.round(((2256 - 5 * 16) / 6) * 1.5));
  });
});
