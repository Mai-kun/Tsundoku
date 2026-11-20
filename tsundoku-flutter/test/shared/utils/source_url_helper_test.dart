import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/utils/source_url_helper.dart';

/// 1:1 port-тест `sourceUrlHelper.ts` (в TS теста не было — покрытие добавлено).
void main() {
  test('LibSocial-экосистема', () {
    expect(buildSourceUrl('MangaLib', '35160--berserk'),
        'https://mangalib.me/ru/35160--berserk');
    expect(buildSourceUrl('ranobelib', '8231--x'),
        'https://ranobelib.me/ru/8231--x');
    expect(
      buildSourceUrl('animelib', 'ru/anime/8231--noragami-anime'),
      'https://v5.animelib.org/ru/anime/8231--noragami-anime',
      reason: '🐛 баг исходника #2 исправлен: префикс зачищается, URL канонический',
    );
    expect(buildSourceUrl('animelib', '8231--x'),
        'https://v5.animelib.org/ru/anime/8231--x');
    expect(buildSourceUrl('slashlib', '1--a'), 'https://slashlib.me/ru/1--a');
    expect(buildSourceUrl('hentailib', '5--b'), 'https://hentailib.me/ru/5--b');
    expect(buildSourceUrl('livelib', '123456'),
        'https://www.livelib.ru/book/123456');
  });

  test('аниме/манга-источники с mediaType', () {
    expect(buildSourceUrl('AniList', '1234', mediaType: 'anime'),
        'https://anilist.co/anime/1234');
    expect(buildSourceUrl('AniList', '1234', mediaType: 'manga'),
        'https://anilist.co/manga/1234');
    expect(buildSourceUrl('AniList', '1234'), 'https://anilist.co/manga/1234',
        reason: 'manga по умолчанию');
    expect(buildSourceUrl('shikimori', '123', mediaType: 'anime'),
        'https://shikimori.io/animes/123');
    expect(buildSourceUrl('shikimori', '123'), 'https://shikimori.io/mangas/123');
    expect(buildSourceUrl('Kitsu', '1', mediaType: 'anime'),
        'https://kitsu.io/anime/1');
    expect(buildSourceUrl('Kitsu', '1'), 'https://kitsu.io/manga/1');
  });

  test('кино/игры/книги', () {
    expect(buildSourceUrl('TMDb', '550', mediaType: 'tvshow'),
        'https://www.themoviedb.org/tv/550');
    expect(buildSourceUrl('The Movie Database', '550'),
        'https://www.themoviedb.org/movie/550');
    expect(buildSourceUrl('Kinopoisk', '123'), 'https://www.kinopoisk.ru/film/123/');
    expect(buildSourceUrl('RAWG', 'hades'), 'https://rawg.io/games/hades');
    expect(buildSourceUrl('IMDb', 'tt0111161'), 'https://www.imdb.com/title/tt0111161/');
    expect(buildSourceUrl('steam', '367520'), 'https://store.steampowered.com/app/367520');
    expect(buildSourceUrl('MangaDex', 'uuid-1'), 'https://mangadex.org/title/uuid-1');
    expect(buildSourceUrl('Simkl', '42'), 'https://simkl.com/42');
    expect(buildSourceUrl('OpenLibrary', '/works/OL1'), 'https://openlibrary.org/works/OL1');
    expect(buildSourceUrl('OpenLibrary', 'works/OL1'), 'https://openlibrary.org/works/OL1');
  });

  test('неизвестный источник / пустой id → null', () {
    expect(buildSourceUrl('unknown-source', '123'), isNull);
    expect(buildSourceUrl('anilist', '   '), isNull);
  });
}
