import { describe, it, expect } from "vitest";
import { chunkIntoRows, columnsForWidth, estimateRowHeight } from "../virtualGrid";

describe("virtualGrid", () => {
  it("matches Tailwind responsive column breakpoints", () => {
    expect(columnsForWidth(0)).toBe(2);
    expect(columnsForWidth(639)).toBe(2);
    expect(columnsForWidth(640)).toBe(3);
    expect(columnsForWidth(1023)).toBe(3);
    expect(columnsForWidth(1024)).toBe(4);
    expect(columnsForWidth(1279)).toBe(4);
    expect(columnsForWidth(1280)).toBe(5);
    expect(columnsForWidth(1535)).toBe(5);
    expect(columnsForWidth(1536)).toBe(7);
    expect(columnsForWidth(2560)).toBe(7);
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
    for (const columns of [2, 3, 4, 5, 7]) {
      const rows = chunkIntoRows(items, columns);
      const flat = rows.flat();
      expect(flat.length).toBe(items.length);
      expect(flat).toEqual(items);
      for (let i = 0; i < rows.length - 1; i++) {
        expect(rows[i].length).toBe(columns);
      }
    }
  });

  it("estimates row height based on width breakpoints", () => {
    expect(estimateRowHeight(0)).toBe(329);
    expect(estimateRowHeight(639)).toBe(329);
    expect(estimateRowHeight(640)).toBe(400);
    expect(estimateRowHeight(1023)).toBe(400);
    expect(estimateRowHeight(1024)).toBe(345);
    expect(estimateRowHeight(1279)).toBe(345);
    expect(estimateRowHeight(1280)).toBe(385);
    expect(estimateRowHeight(1535)).toBe(385);
    expect(estimateRowHeight(1536)).toBe(410);
    expect(estimateRowHeight(2560)).toBe(410);
  });
});
