/// 1:1 port of `mediatracker-ui/src/entities/media/model/coverUrl.ts`.
///
/// The stored `coverUrl` always points at the thumb rendition, which is what
/// the grid renders. `original.webp` sits next to it in the same per-title
/// folder, so the detail page can ask for the full-size file by rewriting the
/// filename — no extra field, no re-download of the cover.
///
/// Anything that is not that exact local pair (an external URL kept because
/// the download failed, or a legacy `/covers/...` row) is returned untouched:
/// those have no sibling file to switch to.
library;

/// thumb → original: подмена имени файла в `/media-assets/<id>/.../thumb.webp`.
String fullSizeCoverUrl(String coverUrl) {
  return coverUrl.replaceFirstMapped(
    RegExp(r'\/media-assets\/([^\/]+)\/(cover|covers\/[^\/]+)\/thumb\.webp(\?.*)?$'),
    (m) => '/media-assets/${m[1]}/${m[2]}/original.webp${m[3] ?? ''}',
  );
}

/// A cover may be a local asset the server already hosts, or an external
/// http(s) link. The native `type="url"` input rejects the local form, which
/// blocked saving a row whose own stored cover was prefilled into the field.
bool isValidCoverUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.startsWith('/')) return true;
  return RegExp(r'^https?:\/\/\S+$', caseSensitive: false).hasMatch(trimmed);
}

/// Every external cover URL routes through the server's
/// /api/external/image-proxy instead of loading straight from its CDN: the
/// proxy fetches with the headers each guard demands (DDoS-Guard answers a
/// plain browser <img> with 403; MangaDex's uploads CDN answers it with a
/// bot-challenge redirect), caches the bytes on disk and serves repeat
/// previews locally — zero requests to the CDN for a cached URL within the
/// server-side TTL. `forceRefresh` skips the disk cache for an explicit
/// re-download.
String proxiedExternalCoverUrl(String coverUrl, {bool forceRefresh = false}) {
  final trimmed = coverUrl.trim();
  if (!RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  // Parseable URL: proxy it. Local asset paths and non-http schemes were
  // already filtered out. The server validates the host again, so a
  // malformed edge case just fails the <img>.
  return '/api/external/image-proxy?url=${Uri.encodeComponent(trimmed)}'
      '${forceRefresh ? '&forceRefresh=true' : ''}';
}
