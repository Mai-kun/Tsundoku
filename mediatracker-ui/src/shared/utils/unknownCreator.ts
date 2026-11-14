/**
 * Placeholder names a source-driven import stores when it learns no author/studio ("Неизвестный
 * автор", "unknown", "n/a", "-"). Treating them as a real creator would group every unlabeled book
 * or manga into one fake "author's works" collection, so the detail page skips the summary query
 * for them entirely.
 */
const UNKNOWN_CREATOR_NAMES = new Set([
  "",
  "-",
  "--",
  "—",
  "n/a",
  "unknown",
  "unknown author",
  "неизвестный автор",
]);

export function isUnknownCreatorName(name: string | null | undefined): boolean {
  if (!name) return true;
  return UNKNOWN_CREATOR_NAMES.has(name.trim().toLowerCase());
}
