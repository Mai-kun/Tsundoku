import { describe, it, expect } from "vitest";
import { fullSizeCoverUrl, isValidCoverUrl } from "../coverUrl";

describe("coverUrl", () => {
  it("resolves stored local thumb to full-size sibling", () => {
    expect(fullSizeCoverUrl("/media-assets/2f1c0b3a/cover/thumb.webp")).toBe(
      "/media-assets/2f1c0b3a/cover/original.webp",
    );
    expect(fullSizeCoverUrl("/media-assets/2f1c0b3a/covers/c123abc/thumb.webp")).toBe(
      "/media-assets/2f1c0b3a/covers/c123abc/original.webp",
    );
  });

  it("preserves query string when swapping to original", () => {
    expect(fullSizeCoverUrl("/media-assets/2f1c0b3a/cover/thumb.webp?v=3")).toBe(
      "/media-assets/2f1c0b3a/cover/original.webp?v=3",
    );
    expect(fullSizeCoverUrl("/media-assets/2f1c0b3a/covers/c123abc/thumb.webp?v=3")).toBe(
      "/media-assets/2f1c0b3a/covers/c123abc/original.webp?v=3",
    );
  });

  it("leaves external and legacy URLs untouched", () => {
    expect(fullSizeCoverUrl("https://image.tmdb.org/t/p/original/abc.jpg")).toBe(
      "https://image.tmdb.org/t/p/original/abc.jpg",
    );
    expect(fullSizeCoverUrl("/covers/legacy-row.webp")).toBe("/covers/legacy-row.webp");
  });

  it("validates cover URLs correctly", () => {
    expect(isValidCoverUrl("/media-assets/2f1c0b3a/cover/thumb.webp")).toBe(true);
    expect(isValidCoverUrl("")).toBe(true);
    expect(isValidCoverUrl("https://image.tmdb.org/t/p/w500/abc.jpg")).toBe(true);
    expect(isValidCoverUrl("http://example.com/a.jpg")).toBe(true);

    expect(isValidCoverUrl("not a url")).toBe(false);
    expect(isValidCoverUrl("ftp://example.com/a.jpg")).toBe(false);
  });
});
