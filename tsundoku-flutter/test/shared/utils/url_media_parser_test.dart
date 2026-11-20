import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/utils/url_media_parser.dart';

/// Прямой перенос vitest-кейсов `urlMediaParser.test.ts`.
void main() {
  group('parseMediaUrl', () {
    test('AniList anime и manga URL', () {
      expect(parseMediaUrl('https://anilist.co/anime/118408/'),
          const ParsedMediaUrl(source: 'anilist', id: '118408', type: 'anime'));
      expect(
          parseMediaUrl('https://anilist.co/manga/118408/lydias-great-escape'),
          const ParsedMediaUrl(source: 'anilist', id: '118408', type: 'manga'));
      expect(parseMediaUrl('anilist.co/manga/54321'),
          const ParsedMediaUrl(source: 'anilist', id: '54321', type: 'manga'));
    });

    test('Shikimori: домены и z-префикс', () {
      expect(parseMediaUrl('https://shikimori.one/animes/z12345-title'),
          const ParsedMediaUrl(source: 'shikimori', id: '12345', type: 'anime'));
      expect(parseMediaUrl('https://shikimori.me/animes/54321'),
          const ParsedMediaUrl(source: 'shikimori', id: '54321', type: 'anime'));
      expect(parseMediaUrl('https://shikimori.io/mangas/9999'),
          const ParsedMediaUrl(source: 'shikimori', id: '9999', type: 'manga'));
      expect(parseMediaUrl('shikimori.me/mangas/z8888-manga-slug'),
          const ParsedMediaUrl(source: 'shikimori', id: '8888', type: 'manga'));
      // Любой будущий TLD тоже парсится:
      expect(parseMediaUrl('https://shikimori.app/animes/777'),
          const ParsedMediaUrl(source: 'shikimori', id: '777', type: 'anime'));
      expect(parseMediaUrl('https://shikimori.wtf/mangas/1234-some-title'),
          const ParsedMediaUrl(source: 'shikimori', id: '1234', type: 'manga'));
    });

    test('MangaDex title URL', () {
      expect(
        parseMediaUrl(
            'https://mangadex.org/title/a9667631-b79e-4721-9749-cbf975a5a032/sousou-no-frieren'),
        const ParsedMediaUrl(
            source: 'mangadex',
            id: 'a9667631-b79e-4721-9749-cbf975a5a032',
            type: 'manga'),
      );
      expect(
        parseMediaUrl('mangadex.org/title/a9667631-b79e-4721-9749-cbf975a5a032'),
        const ParsedMediaUrl(
            source: 'mangadex',
            id: 'a9667631-b79e-4721-9749-cbf975a5a032',
            type: 'manga'),
      );
    });

    test('TMDb movie/tv', () {
      expect(parseMediaUrl('https://www.themoviedb.org/movie/550-fight-club'),
          const ParsedMediaUrl(source: 'tmdb', id: '550', type: 'movie'));
      expect(parseMediaUrl('https://www.themoviedb.org/tv/1399-game-of-thrones'),
          const ParsedMediaUrl(source: 'tmdb', id: '1399', type: 'tvshow'));
    });

    test('IMDb', () {
      expect(parseMediaUrl('https://www.imdb.com/title/tt0111161/'),
          const ParsedMediaUrl(source: 'imdb', id: 'tt0111161', type: 'movie'));
    });

    test('Steam', () {
      expect(
          parseMediaUrl('https://store.steampowered.com/app/1086940/Baldurs_Gate_3/'),
          const ParsedMediaUrl(source: 'steam', id: '1086940', type: 'game'));
    });

    test('RAWG', () {
      expect(parseMediaUrl('https://rawg.io/games/the-witcher-3-wild-hunt'),
          const ParsedMediaUrl(
              source: 'rawg', id: 'the-witcher-3-wild-hunt', type: 'game'));
    });

    test('RanobeLib / MangaLib / AnimeLib', () {
      expect(parseMediaUrl('https://ranobelib.me/ru/1234-some-novel'),
          const ParsedMediaUrl(
              source: 'ranobelib', id: '1234-some-novel', type: 'book'));
      expect(parseMediaUrl('https://mangalib.me/some-manga'),
          const ParsedMediaUrl(source: 'mangalib', id: 'some-manga', type: 'manga'));
      expect(parseMediaUrl('https://animelib.org/some-anime'),
          const ParsedMediaUrl(source: 'animelib', id: 'some-anime', type: 'anime'));
      // Живой AnimeLib-вид: версионный поддомен, обязательные /ru/anime/.
      expect(
        parseMediaUrl('https://v5.animelib.org/ru/anime/8231--noragami-anime'),
        const ParsedMediaUrl(
            source: 'animelib', id: '8231--noragami-anime', type: 'anime'),
      );
      // Будущие версии и неизвестные TLD — то же:
      expect(
        parseMediaUrl('https://v6.animelib.app/ru/anime/8231--noragami-anime'),
        const ParsedMediaUrl(
            source: 'animelib', id: '8231--noragami-anime', type: 'anime'),
      );
      // Системные страницы → null:
      expect(parseMediaUrl('https://mangalib.me/ru/catalog'), isNull);
      expect(parseMediaUrl('https://mangalib.me/bookmarks'), isNull);
      expect(parseMediaUrl('https://v5.animelib.org/ru/anime/catalog'), isNull);
    });

    test('текущий RanobeLib /ru/manga/{id}--{slug}', () {
      expect(
        parseMediaUrl('https://ranobelib.me/ru/manga/202007--shoushimin-series'),
        const ParsedMediaUrl(
            source: 'ranobelib', id: '202007--shoushimin-series', type: 'book'),
      );
      expect(
        parseMediaUrl('https://ranobelib.me/ru/ranobe/195--naruto'),
        const ParsedMediaUrl(
            source: 'ranobelib', id: '195--naruto', type: 'book'),
      );
      expect(
        parseMediaUrl('ranobelib.me/195--naruto'),
        const ParsedMediaUrl(
            source: 'ranobelib', id: '195--naruto', type: 'book'),
      );
    });

    test('вся Lib-семья: slashlib, hentailib, lib.social и manga-деревья', () {
      expect(
        parseMediaUrl('https://slashlib.me/ru/manga/35160--solo-leveling'),
        const ParsedMediaUrl(
            source: 'mangalib', id: '35160--solo-leveling', type: 'manga'),
      );
      expect(
        parseMediaUrl('https://hentailib.me/ru/manga/402--some-title'),
        const ParsedMediaUrl(
            source: 'mangalib', id: '402--some-title', type: 'manga'),
      );
      expect(
        parseMediaUrl('https://lib.social/manga/35160--solo-leveling'),
        const ParsedMediaUrl(
            source: 'mangalib', id: '35160--solo-leveling', type: 'manga'),
      );
      expect(
        parseMediaUrl('https://mangalib.me/ru/manga/11214--one-piece'),
        const ParsedMediaUrl(
            source: 'mangalib', id: '11214--one-piece', type: 'manga'),
      );
    });

    test('Kitsu anime/manga', () {
      expect(parseMediaUrl('https://kitsu.app/anime/cowboy-bebop'),
          const ParsedMediaUrl(
              source: 'kitsu', id: 'cowboy-bebop', type: 'anime'));
      expect(parseMediaUrl('https://kitsu.io/manga/berserk'),
          const ParsedMediaUrl(source: 'kitsu', id: 'berserk', type: 'manga'));
    });

    test('Steam store/community со слагами и query', () {
      expect(
        parseMediaUrl('https://store.steampowered.com/app/2237970/Lies_of_P/'),
        const ParsedMediaUrl(source: 'steam', id: '2237970', type: 'game'),
      );
      expect(parseMediaUrl('https://store.steampowered.com/app/2237970'),
          const ParsedMediaUrl(source: 'steam', id: '2237970', type: 'game'));
      expect(
        parseMediaUrl(
            'https://store.steampowered.com/app/292030/The_Witcher_3_Wild_Hunt/?l=russian'),
        const ParsedMediaUrl(source: 'steam', id: '292030', type: 'game'),
      );
      expect(parseMediaUrl('https://steamcommunity.com/app/2237970'),
          const ParsedMediaUrl(source: 'steam', id: '2237970', type: 'game'));
    });

    test('OpenLibrary ISBN/edition/work', () {
      expect(parseMediaUrl('https://openlibrary.org/isbn/9780140328721'),
          const ParsedMediaUrl(
              source: 'openlibrary', id: '9780140328721', type: 'book'));
      expect(parseMediaUrl('https://openlibrary.org/isbn/978-0-14-032872-1'),
          const ParsedMediaUrl(
              source: 'openlibrary', id: '9780140328721', type: 'book'));
      expect(parseMediaUrl('https://openlibrary.org/books/OL7353617M'),
          const ParsedMediaUrl(
              source: 'openlibrary', id: 'OL7353617M', type: 'book'));
      expect(parseMediaUrl('https://openlibrary.org/works/OL45804W'),
          const ParsedMediaUrl(
              source: 'openlibrary', id: 'OL45804W', type: 'book'));
    });

    test('не-URL и обычные поисковые строки → null', () {
      expect(parseMediaUrl(''), isNull);
      expect(parseMediaUrl('Naruto'), isNull);
      expect(parseMediaUrl('https://google.com/search?q=test'), isNull);
      expect(parseMediaUrl('   '), isNull);
      expect(parseMediaUrl(null), isNull);
    });
  });

  group('isIsbn / isUrl / detectQueryBadge', () {
    test('isIsbn: ISBN-10 и ISBN-13', () {
      expect(isIsbn('9780140328721'), isTrue);
      expect(isIsbn('978-0-14-032872-1'), isTrue);
      expect(isIsbn('isbn:9780140328721'), isTrue);
      expect(isIsbn('ISBN:978-0-14-032872-1'), isTrue);
      expect(isIsbn('0451526538'), isTrue); // ISBN-10 (0-9 + контрольный)
      expect(isIsbn('045152653X'), isTrue); // X-контрольный
      expect(isIsbn('not an isbn'), isFalse);
      expect(isIsbn('123'), isFalse);
      expect(isIsbn(''), isFalse);
      expect(isIsbn(null), isFalse);
    });

    test('isUrl', () {
      expect(isUrl('https://example.com'), isTrue);
      expect(isUrl('HTTP://EXAMPLE.COM'), isTrue);
      expect(isUrl('ftp://example.com'), isFalse);
      expect(isUrl('Naruto'), isFalse);
      expect(isUrl(''), isFalse);
      expect(isUrl(null), isFalse);
    });

    test('detectQueryBadge: LINK / ISBN / null', () {
      expect(detectQueryBadge('https://anilist.co/anime/1'),
          const QueryBadge(QueryBadgeType.link));
      expect(detectQueryBadge('  https://anilist.co/anime/1 '),
          const QueryBadge(QueryBadgeType.link));
      expect(detectQueryBadge('978-0-14-032872-1'),
          const QueryBadge(QueryBadgeType.isbn));
      expect(detectQueryBadge('isbn:9780140328721'),
          const QueryBadge(QueryBadgeType.isbn));
      expect(detectQueryBadge('Naruto'), isNull);
      expect(detectQueryBadge(''), isNull);
      expect(detectQueryBadge(null), isNull);
    });

    test('QueryBadgeType wire 1-в-1 (LINK/ISBN)', () {
      expect(QueryBadgeType.link.wire, 'LINK');
      expect(QueryBadgeType.isbn.wire, 'ISBN');
    });
  });
}
