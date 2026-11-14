/**
 * The stored `coverUrl` always points at the thumb rendition, which is what the grid renders.
 * `original.webp` sits next to it in the same per-title folder, so the detail page can ask for the
 * full-size file by rewriting the filename — no extra field, no re-download of the cover.
 *
 * Anything that is not that exact local pair (an external URL kept because the download failed, or a
 * legacy `/covers/...` row) is returned untouched: those have no sibling file to switch to.
 */
export function fullSizeCoverUrl(coverUrl: string): string {
  return coverUrl.replace(
    /\/media-assets\/([^/]+)\/(cover|covers\/[^/]+)\/thumb\.webp(\?.*)?$/,
    "/media-assets/$1/$2/original.webp$3",
  );
}

/**
 * A cover may be a local asset the server already hosts, or an external http(s) link. The native
 * `type="url"` input rejects the local form, which blocked saving a row whose own stored cover was
 * prefilled into the field.
 */
export function isValidCoverUrl(value: string): boolean {
  const trimmed = value.trim();
  return trimmed === "" || trimmed.startsWith("/") || /^https?:\/\/\S+$/i.test(trimmed);
}

/**
 * Every external cover URL routes through the server's /api/external/image-proxy instead of
 * loading straight from its CDN: the proxy fetches with the headers each guard demands
 * (DDoS-Guard answers a plain browser <img> with 403; MangaDex's uploads CDN answers it with a
 * bot-challenge redirect), caches the bytes on disk and serves repeat previews locally — zero
 * requests to the CDN for a cached URL within the server-side TTL. `forceRefresh` skips the
 * disk cache for an explicit re-download.
 */
export function proxiedExternalCoverUrl(coverUrl: string, forceRefresh = false): string {
  const trimmed = coverUrl.trim();
  if (!/^https?:\/\//i.test(trimmed)) return trimmed;
  try {
    // Parseable URL: proxy it. Local asset paths and non-http schemes were already filtered out.
    // The server validates the host again, so a malformed edge case just fails the <img>.
    return `/api/external/image-proxy?url=${encodeURIComponent(trimmed)}${
      forceRefresh ? "&forceRefresh=true" : ""
    }`;
  } catch {
    // Not a parseable URL: leave it alone and let the <img> handle the failure.
    return trimmed;
  }
}
