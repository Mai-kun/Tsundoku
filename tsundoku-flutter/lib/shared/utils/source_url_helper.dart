/// 1:1 port of `mediatracker-ui/src/shared/utils/sourceUrlHelper.ts`.
///
/// Builds the real web page of a title for a bound external source. Unknown
/// or offline sources return null — the panel then renders the card without
/// the "open" action.
library;

/// AnimeLib lives on a versioned subdomain with mandatory /ru/anime/ path
/// prefixes. A stored slug that already carries them ("ru/anime/8231--x") is
/// stripped before substitution, so the result is always canonical:
/// https://v5.animelib.org/ru/anime/8231--noragami-anime.
String buildAnimelibUrl(String id) {
  final cleanSlug =
      id.trim().replaceFirst(RegExp(r'^(?:ru\/)?(?:anime\/)?', caseSensitive: false), '');
  return 'https://v5.animelib.org/ru/anime/${Uri.encodeComponent(cleanSlug)}';
}

String? buildSourceUrl(String source, String externalId,
    {String? mediaType}) {
  final key = source.toLowerCase();
  final id = Uri.encodeComponent(externalId.trim());
  // OpenLibrary использует сырой путь (starts-with '/' — путь целиком).
  final rawId = externalId.trim();
  if (id.isEmpty) return null;

  // LiveLib: the stored id is the numeric book id; the site resolves it to
  // the full slug itself.
  if (key.contains('livelib')) return 'https://www.livelib.ru/book/$id';

  // LibSocial ecosystem: the stored id is the site's slug_url ("35160--slug").
  if (key.contains('mangalib')) return 'https://mangalib.me/ru/$id';
  if (key.contains('ranobelib')) return 'https://ranobelib.me/ru/$id';
  if (key.contains('animelib')) {
    // 🐛 Баг исходника Svelte #2 (см. FLUTTER_MIGRATION.md «Лог багов»):
    // в TS сюда уходил уже encodeURIComponent-нутый id, и зачистка
    // префикса "ru/anime/" не срабатывала → двойное кодирование
    // (ru%252F...). Исправлено: передаётся сырой id.
    return buildAnimelibUrl(rawId);
  }
  if (key.contains('slashlib')) return 'https://slashlib.me/ru/$id';
  if (key.contains('hentailib')) return 'https://hentailib.me/ru/$id';

  if (key.contains('anilist')) {
    final kind = mediaType == 'anime' ? 'anime' : 'manga';
    return 'https://anilist.co/$kind/$id';
  }
  if (key.contains('shikimori')) {
    // The site moved off shikimori.one (it stopped answering); .io is the
    // live domain.
    return mediaType == 'anime'
        ? 'https://shikimori.io/animes/$id'
        : 'https://shikimori.io/mangas/$id';
  }
  if (key.contains('mangadex')) return 'https://mangadex.org/title/$id';
  if (key.contains('steam')) return 'https://store.steampowered.com/app/$id';
  if (key.contains('tmdb') || key.contains('movie database')) {
    final kind = mediaType == 'tvshow' ? 'tv' : 'movie';
    return 'https://www.themoviedb.org/$kind/$id';
  }
  if (key.contains('kinopoisk')) return 'https://www.kinopoisk.ru/film/$id/';
  if (key.contains('rawg')) return 'https://rawg.io/games/$id';
  if (key.contains('imdb')) return 'https://www.imdb.com/title/$id/';
  if (key.contains('openlibrary')) {
    return 'https://openlibrary.org${rawId.startsWith('/') ? rawId : '/$rawId'}';
  }
  if (key.contains('kitsu')) {
    // Kitsu keeps novels and manga in one /manga tree; only anime gets its
    // own section.
    return mediaType == 'anime'
        ? 'https://kitsu.io/anime/$id'
        : 'https://kitsu.io/manga/$id';
  }
  if (key.contains('simkl')) return 'https://simkl.com/$id';

  return null;
}
