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
        /\/media-assets\/([^/]+)\/cover\/thumb\.webp(\?.*)?$/,
        "/media-assets/$1/cover/original.webp$2",
    );
}

/**
 * A cover may be a local asset the server already hosts, or an external http(s) link. The native
 * `type="url"` input rejects the local form, which blocked saving a row whose own stored cover was
 * prefilled into the field.
 */
export function isValidCoverUrl(value: string): boolean {
    const trimmed = value.trim();
    return (
        trimmed === "" ||
        trimmed.startsWith("/") ||
        /^https?:\/\/\S+$/i.test(trimmed)
    );
}