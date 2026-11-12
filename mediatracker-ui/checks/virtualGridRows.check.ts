// Self-check for the virtual grid helpers: viewport breakpoints must mirror the
// Tailwind classes of the card grid (grid-cols-2 sm:3 lg:4 xl:5 2xl:6), and row
// chunking must never drop or reorder items. Run: `npm run check:virtual-grid-rows`
// (node --experimental-strip-types). No framework, no fixtures, no network.
import assert from "node:assert/strict";
import {
    chunkIntoRows,
    columnsForWidth,
    estimateRowHeight,
} from "../src/widgets/media-grid/virtualGrid.ts";

// 1. Breakpoints mirror the Tailwind responsive classes exactly.
{
    assert.equal(columnsForWidth(0), 2, "tiny viewport still gets 2 columns");
    assert.equal(columnsForWidth(639), 2, "< 640px: 2 columns");
    assert.equal(columnsForWidth(640), 3, "sm (640px): 3 columns");
    assert.equal(columnsForWidth(1023), 3, "< lg: 3 columns");
    assert.equal(columnsForWidth(1024), 4, "lg (1024px): 4 columns");
    assert.equal(columnsForWidth(1279), 4, "< xl: 4 columns");
    assert.equal(columnsForWidth(1280), 5, "xl (1280px): 5 columns");
    assert.equal(columnsForWidth(1535), 5, "< 2xl: 5 columns");
    assert.equal(columnsForWidth(1536), 6, "2xl (1536px): 6 columns");
    assert.equal(columnsForWidth(2560), 6, "wide screens stay at 6 columns");
}

// 2. A full page splits evenly, a remainder lands on the last row.
{
    assert.deepEqual(chunkIntoRows([1, 2, 3, 4, 5, 6, 7], 7), [[1, 2, 3, 4, 5, 6, 7]], "exact single row");
    assert.deepEqual(
        chunkIntoRows([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], 7),
        [
            [1, 2, 3, 4, 5, 6, 7],
            [8, 9, 10, 11, 12, 13, 14],
        ],
        "two full rows",
    );
    assert.deepEqual(
        chunkIntoRows([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], 7),
        [[1, 2, 3, 4, 5, 6, 7], [8, 9, 10, 11, 12, 13]],
        "remainder row holds the leftovers",
    );
    assert.deepEqual(chunkIntoRows([1, 2, 3], 7), [[1, 2, 3]], "list smaller than a row");
    assert.deepEqual(chunkIntoRows([], 7), [], "empty list has no rows");
}

// 3. Chunking preserves order and every item, whatever the column count.
{
    const items = Array.from({ length: 100 }, (_, i) => i);
    for (const columns of [2, 3, 4, 5, 7]) {
        const flat = chunkIntoRows(items, columns).flat();
        assert.equal(flat.length, items.length, `${columns} cols keep all items`);
        assert.deepEqual(flat, items, `${columns} cols keep the order`);
        const rows = chunkIntoRows(items, columns);
        for (let i = 0; i < rows.length - 1; i++) {
            assert.equal(rows[i].length, columns, `row ${i} is full`);
        }
    }
}

// 4. Seed estimates for the fixed per-breakpoint row height. Rows are uniform
//    within a breakpoint (2:3 poster, no info block) but differ across them, so
//    a single flat constant would overlap rows on wide screens. MediaGrid
//    corrects the seed with one measurement of the first rendered row.
{
    assert.equal(estimateRowHeight(0), 213, "2 cols, clamped 300px content width");
    assert.equal(estimateRowHeight(639), 419, "2 cols up to sm");
    assert.equal(estimateRowHeight(640), 272, "3 cols range 640-1023");
    assert.equal(estimateRowHeight(1023), 464, "3 cols up to lg");
    assert.equal(estimateRowHeight(1024), 252, "4 cols at lg");
    assert.equal(estimateRowHeight(1279), 348, "4 cols up to xl");
    assert.equal(estimateRowHeight(1280), 274, "5 cols range 1280-1535");
    assert.equal(estimateRowHeight(1535), 350, "5 cols up to 2xl");
    assert.equal(estimateRowHeight(1536), 288, "6 cols at 2xl");
    assert.equal(estimateRowHeight(2560), 544, "wide screens stay at 6 cols");
}

console.log("ok   virtual grid columns mirror Tailwind breakpoints and rows keep every item");
