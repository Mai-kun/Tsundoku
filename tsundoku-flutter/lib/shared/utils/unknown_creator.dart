/// 1:1 port of `mediatracker-ui/src/shared/utils/unknownCreator.ts`.
///
/// Placeholder names a source-driven import stores when it learns no
/// author/studio ("Неизвестный автор", "unknown", "n/a", "-"). Treating them
/// as a real creator would group every unlabeled book or manga into one fake
/// "author's works" collection, so the detail page skips the summary query
/// for them entirely.
library;

const Set<String> _unknownCreatorNames = <String>{
  '',
  '-',
  '--',
  '—',
  'n/a',
  'unknown',
  'unknown author',
  'неизвестный автор',
};

bool isUnknownCreatorName(String? name) {
  if (name == null || name.isEmpty) return true;
  return _unknownCreatorNames.contains(name.trim().toLowerCase());
}
