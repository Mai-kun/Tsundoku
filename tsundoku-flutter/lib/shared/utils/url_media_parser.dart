/// 1:1 port of `mediatracker-ui/src/shared/utils/urlMediaParser.ts`.
///
/// Парсинг URL внешних источников в (source, externalId, type) по списку
/// regex-правил + классификация строки поиска (URL/ISBN-бейдж).
library;

const Set<String> _forbiddenSlugs = <String>{
  'user',
  'users',
  'catalog',
  'bookmarks',
  'folder',
  'login',
  'register',
  'settings',
  'faq',
  'rules',
  'team',
  'teams',
  'latest',
};

class ParsedMediaUrl {
  final String source;
  final String id;
  final String type; // SearchMediaType — открытый строковый union.

  const ParsedMediaUrl({
    required this.source,
    required this.id,
    required this.type,
  });

  @override
  bool operator ==(Object other) =>
      other is ParsedMediaUrl &&
      other.source == source &&
      other.id == id &&
      other.type == type;

  @override
  int get hashCode => Object.hash(source, id, type);

  @override
  String toString() => 'ParsedMediaUrl($source, $id, $type)';
}

String? _m1(List<String?> m) => m[1];
String? _shikimoriId(List<String?> m) => m[1] ?? m[2];
String? _m1LowerNoSlashes(List<String?> m) =>
    (m[1] ?? '').replaceAll(RegExp(r'[\s\-]'), '');

/// extractId-правило с фильтром запрещённых слагов (LibSocial/AnimeLib/RanobeLib).
String? Function(List<String?> m) _noForbiddenSlugs() =>
    (m) {
      final id = (m[1] ?? '').toLowerCase();
      return _forbiddenSlugs.contains(id) ? null : m[1];
    };

class _MatchRule {
  final RegExp pattern;
  final String source;
  final String type;
  final String? Function(List<String?> m) extractId;
  const _MatchRule(this.pattern, this.source, this.type, this.extractId);
}

final List<_MatchRule> _rules = <_MatchRule>[
  // AniList
  _MatchRule(RegExp(r'anilist\.co\/anime\/(\d+)', caseSensitive: false),
      'anilist', 'anime', _m1),
  _MatchRule(RegExp(r'anilist\.co\/manga\/(\d+)', caseSensitive: false),
      'anilist', 'manga', _m1),

  // Shikimori — the domain moves regularly (.one, .io, .me, shikimori.app...),
  // so any TLD matches.
  _MatchRule(
      RegExp(r'shikimori\.[a-z]{2,6}\/animes\/(?:z?(\d+)|(\d+))',
          caseSensitive: false),
      'shikimori',
      'anime',
      _shikimoriId),
  _MatchRule(
      RegExp(r'shikimori\.[a-z]{2,6}\/mangas\/(?:z?(\d+)|(\d+))',
          caseSensitive: false),
      'shikimori',
      'manga',
      _shikimoriId),

  // MangaDex
  _MatchRule(RegExp(r'mangadex\.org\/title\/([a-f0-9\-]+)', caseSensitive: false),
      'mangadex', 'manga', _m1),

  // TMDb
  _MatchRule(RegExp(r'themoviedb\.org\/movie\/(\d+)', caseSensitive: false),
      'tmdb', 'movie', _m1),
  _MatchRule(RegExp(r'themoviedb\.org\/tv\/(\d+)', caseSensitive: false),
      'tmdb', 'tvshow', _m1),

  // IMDb
  _MatchRule(RegExp(r'imdb\.com\/title\/(tt\d+)', caseSensitive: false),
      'imdb', 'movie', _m1),

  // Steam — store and community links, with or without the title slug and
  // query string (?snr=..., /?l=russian): /app/2237970, /app/2237970/Lies_of_P/,
  // steamcommunity.com/app/2237970.
  _MatchRule(
      RegExp(r'(?:store\.steampowered|steamcommunity)\.com\/app\/(\d+)',
          caseSensitive: false),
      'steam',
      'game',
      _m1),

  // OpenLibrary — direct links: the ISBN form resolves through the exact isbn
  // index, edition (books/OL…M) and work (works/OL…W) links resolve through
  // the search index's key: field.
  _MatchRule(RegExp(r'openlibrary\.org\/isbn\/([0-9Xx\-]+)', caseSensitive: false),
      'openlibrary', 'book', _m1LowerNoSlashes),
  _MatchRule(RegExp(r'openlibrary\.org\/(?:books|works)\/(OL\w+)', caseSensitive: false),
      'openlibrary', 'book', _m1),

  // RAWG
  _MatchRule(RegExp(r'rawg\.io\/games\/([a-z0-9\-]+)', caseSensitive: false),
      'rawg', 'game', _m1),

  // LibSocial ecosystem: MangaLib / SlashLib / HentaiLib / lib.social (manga
  // sites). Ids arrive both as bare slugs and as "35160--slug" pairs; /ru/ and
  // /manga/ or /ranobe/ path segments are optional.
  _MatchRule(
      RegExp(
          r'(?:mangalib\.(?:me|org)|slashlib\.me|hentailib\.me|lib\.social)\/(?:ru\/)?(?:manga\/|ranobe\/)?([0-9a-zA-Z\-_]+)',
          caseSensitive: false),
      'mangalib',
      'manga',
      _noForbiddenSlugs()),
  // AnimeLib — versioned subdomains (v5.animelib.org, v6.?, ...) and any TLD;
  // the /ru/ language prefix and the /anime/ category are optional, so bare
  // animelib.me/anime/... parses too.
  _MatchRule(
      RegExp(
          r'(?:v\d+\.)?animelib\.[a-z]{2,6}\/(?:ru\/)?(?:anime\/)?([0-9a-zA-Z\-_]+)',
          caseSensitive: false),
      'animelib',
      'anime',
      _noForbiddenSlugs()),
  // RanobeLib — novels, but the site also hosts manga trees; the /ru/ language
  // prefix and the /ranobe/ or /manga/ category are optional, so the current
  // "/ru/manga/202007--slug" shape resolves to the title id, not to the
  // literal "manga" segment.
  _MatchRule(
      RegExp(r'ranobelib\.me\/(?:ru\/)?(?:ranobe\/|manga\/)?([0-9a-zA-Z\-_]+)',
          caseSensitive: false),
      'ranobelib',
      'book',
      _noForbiddenSlugs()),

  // Kitsu
  _MatchRule(RegExp(r'kitsu\.(?:app|io)\/anime\/([a-z0-9\-]+)', caseSensitive: false),
      'kitsu', 'anime', _m1),
  _MatchRule(RegExp(r'kitsu\.(?:app|io)\/manga\/([a-z0-9\-]+)', caseSensitive: false),
      'kitsu', 'manga', _m1),
];

/// Parses a media URL and returns the detected source, external ID, and media
/// type. Returns null if the URL is not recognized or not a valid media link.
ParsedMediaUrl? parseMediaUrl(String? input) {
  if (input == null || input.isEmpty) return null;
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  for (final rule in _rules) {
    final match = rule.pattern.firstMatch(trimmed);
    if (match != null) {
      // firstMatch/Match — группы как в TS m[1], m[2]: null для неучастия.
      final groups = <String?>[
        for (var i = 0; i <= match.groupCount; i++) i == 0 ? match.input : match.group(i),
      ];
      final id = rule.extractId(groups);
      if (id != null && id.isNotEmpty) {
        return ParsedMediaUrl(source: rule.source, id: id, type: rule.type);
      }
    }
  }

  return null;
}

/// `"LINK" | "ISBN"`.
enum QueryBadgeType {
  link('LINK'),
  isbn('ISBN');

  final String wire;
  const QueryBadgeType(this.wire);
}

class QueryBadge {
  final QueryBadgeType type;
  const QueryBadge(this.type);

  @override
  bool operator ==(Object other) => other is QueryBadge && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

bool isIsbn(String? input) {
  if (input == null || input.isEmpty) return false;
  final cleaned = input
      .trim()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceFirst(RegExp(r'^isbn:', caseSensitive: false), '');
  return RegExp(r'^(?:\d{9}[\dxX]|\d{13})$').hasMatch(cleaned);
}

bool isUrl(String? input) {
  if (input == null || input.isEmpty) return false;
  return RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(input.trim());
}

QueryBadge? detectQueryBadge(String? input) {
  if (input == null || input.isEmpty) return null;
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  if (isUrl(trimmed)) {
    return const QueryBadge(QueryBadgeType.link);
  }
  if (isIsbn(trimmed)) {
    return const QueryBadge(QueryBadgeType.isbn);
  }
  return null;
}
