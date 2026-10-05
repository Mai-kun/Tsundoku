// Self-check for the cover-URL rules introduced with the poster-quality fix: the detail page must
// resolve the stored thumb URL to the full-size sibling, and the edit form must accept a local asset
// path as readily as an external link. Run: `npm run check:cover` (node --experimental-strip-types).
// No framework, no fixtures, no network.
import assert from "node:assert/strict";
import {
    fullSizeCoverUrl,
    isValidCoverUrl,
} from "../src/entities/media/model/coverUrl.ts";

// 1. The stored local thumb resolves to the full-size file sitting next to it.
assert.equal(
    fullSizeCoverUrl("/media-assets/2f1c0b3a/cover/thumb.webp"),
    "/media-assets/2f1c0b3a/cover/original.webp",
    "thumb resolves to the full-size sibling",
);

// 2. A cache-busting query string survives the swap.
assert.equal(
    fullSizeCoverUrl("/media-assets/2f1c0b3a/cover/thumb.webp?v=3"),
    "/media-assets/2f1c0b3a/cover/original.webp?v=3",
    "query string is preserved",
);

// 3. A cover the server never downloaded has no local sibling, so it is passed through untouched
//    rather than rewritten into a URL that 404s.
assert.equal(
    fullSizeCoverUrl("https://image.tmdb.org/t/p/original/abc.jpg"),
    "https://image.tmdb.org/t/p/original/abc.jpg",
    "external URL untouched",
);
assert.equal(
    fullSizeCoverUrl("/covers/legacy-row.webp"),
    "/covers/legacy-row.webp",
    "legacy /covers row untouched",
);

// 4. The edit form accepts a local cover path: this is the exact value the server stores for a
//    downloaded cover, and rejecting it is what used to block saving an edited title.
assert.equal(
    isValidCoverUrl("/media-assets/2f1c0b3a/cover/thumb.webp"),
    true,
    "local cover path accepted",
);
assert.equal(isValidCoverUrl(""), true, "empty cover accepted (leave unchanged)");
assert.equal(
    isValidCoverUrl("https://image.tmdb.org/t/p/w500/abc.jpg"),
    true,
    "https accepted",
);
assert.equal(isValidCoverUrl("http://example.com/a.jpg"), true, "http accepted");

// 5. Genuinely malformed values are still rejected.
assert.equal(isValidCoverUrl("not a url"), false, "free text rejected");
assert.equal(isValidCoverUrl("ftp://example.com/a.jpg"), false, "non-http scheme rejected");

console.log("cover url rules: ok");