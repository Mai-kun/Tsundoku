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
 * Hosts whose image CDNs block hotlinking (DDoS-Guard answers a plain browser <img> with 403).
 * The server's /api/external/image-proxy fetches these with the headers the guard demands, so
 * external previews route through it; every other host keeps loading straight from its CDN.
 */
const HOTLINK_BLOCKED_HOST_SUFFIXES = ["imglib.info", "mangalib.me"];

/**
 * Rewrites an external cover URL to the server-side image proxy when its host needs it. Local
 * asset paths and regular CDNs are returned untouched, and a malformed URL falls through as-is.
 */
export function proxiedExternalCoverUrl(coverUrl: string): string {
  const trimmed = coverUrl.trim();
  if (!/^https?:\/\//i.test(trimmed)) return trimmed;
  try {
    const host = new URL(trimmed).host;
    if (HOTLINK_BLOCKED_HOST_SUFFIXES.some((suffix) => host.endsWith(suffix))) {
      return `/api/external/image-proxy?url=${encodeURIComponent(trimmed)}`;
    }
  } catch {
    // Not a parseable URL: leave it alone and let the <img> handle the failure.
  }
  return trimmed;
}
