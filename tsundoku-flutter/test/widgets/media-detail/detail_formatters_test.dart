import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Color;
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_formatters.dart';

/// Тесты `detailFormatters.ts` → detail_formatters.dart: типы/форматы,
/// providerLink по всем источникам, статусы релиза, прогресс, серии, specRows.
void main() {
  const ru = Locale.ru;
  const en = Locale.en;
  final ruT = I18nDictionary(ru);
  final enT = I18nDictionary(en);

  Map<String, Object?> baseJson([Map<String, Object?>? extra]) =>
      {
        'id': 'm1',
        'type': 'book',
        'title': 'Властелин колец',
        'status': 2,
        'createdAt': '2024-01-01T00:00:00Z',
        ...?extra,
      };

  MediaItem item([Map<String, Object?> extra = const {}]) =>
      MediaItem.fromJson(baseJson(extra));

  group('isAnime / typeLabel / formatLabel', () {
    test('isAnime: только tvshow/movie с isAnime', () {
      expect(isAnime(item({'type': 'tvshow', 'isAnime': true})), isTrue);
      expect(isAnime(item({'type': 'movie', 'isAnime': true})), isTrue);
      expect(isAnime(item({'type': 'tvshow', 'isAnime': false})), isFalse);
      expect(isAnime(item({'type': 'manga', 'isAnime': true})), isFalse);
    });

    test('typeLabel: anime-привилка и types[type]', () {
      expect(typeLabel(item({'type': 'tvshow', 'isAnime': true}), ruT),
          'Аниме');
      expect(typeLabel(item({'type': 'book'}), ruT), 'Книга');
      expect(typeLabel(item({'type': 'game'}), enT), 'Game');
    });

    test('formatLabel: book-форматы ru/en', () {
      expect(formatLabel(item({'format': 'light_novel'}), ruT), 'Ранобэ');
      expect(formatLabel(item({'format': 'light_novel'}), enT), 'Light Novel');
      expect(formatLabel(item({'format': 'web_novel'}), ruT), 'Веб-новелла');
      expect(formatLabel(item({'format': 'comics'}), ruT), 'Комикс');
      expect(formatLabel(item({'format': 'ebook'}), ruT), 'Электронная книга');
      expect(formatLabel(item({'format': 'audiobook'}), enT), 'Audiobook');
      expect(formatLabel(item({}), ruT), 'Книга');
    });

    test('formatLabel: manga через mangaFormats с фолбэком', () {
      expect(formatLabel(item({'type': 'manga', 'mangaFormat': 'manhwa'}), ruT),
          'Манхва');
      // Неизвестный формат → typeLabel.
      expect(formatLabel(item({'type': 'manga', 'mangaFormat': '???'}), ruT),
          'Манга');
      // Без формата → typeLabel.
      expect(formatLabel(item({'type': 'manga'}), ruT), 'Манга');
    });
  });

  group('dataSource', () {
    test('primary linkedSource (только MediaDetail) приоритетен', () {
      final detail = MediaDetail.fromJson({
        ...baseJson({'externalSource': 'tmdb'}),
        'linkedSources': [
          {'source': 'Kinopoisk', 'externalId': '1', 'isPrimary': false},
          {'source': 'Shikimori', 'externalId': '2', 'isPrimary': true},
        ],
      });
      expect(dataSource(detail), 'Shikimori');
    });

    test('fallback: externalSource → типовые дефолты', () {
      expect(dataSource(item({'externalSource': 'shikimori'})), 'shikimori');
      expect(dataSource(item({'type': 'game'})), 'RAWG');
      expect(dataSource(item({'type': 'book'})), 'OpenLibrary');
      expect(dataSource(item({'type': 'manga'})), 'AniList');
      expect(dataSource(item({'type': 'tvshow'})), 'TMDB');
      expect(dataSource(item({'type': 'tvshow', 'isAnime': true})), 'AniList');
    });
  });

  group('providerLink', () {
    test('primary с url → прямой passthrough', () {
      final detail = MediaDetail.fromJson({
        ...baseJson(),
        'linkedSources': [
          {
            'source': 'Kinopoisk',
            'externalId': '123',
            'isPrimary': true,
            'url': 'https://www.kinopoisk.ru/film/123/',
          },
        ],
      });
      expect(providerLink(detail)!.url, 'https://www.kinopoisk.ru/film/123/');
    });

    test('kinopoisk с id / без id', () {
      expect(providerLink(item({'externalSource': 'kinopoisk', 'externalId': '42'}))!.url,
          'https://www.kinopoisk.ru/film/42/');
      expect(providerLink(item({'externalSource': 'kinopoisk'})), isNull);
    });

    test('tmdb: tv для сериала/аниме, movie для остальных', () {
      expect(providerLink(item({'externalSource': 'tmdb', 'externalId': '9'}))!.url,
          'https://www.themoviedb.org/movie/9');
      expect(
          providerLink(item({'externalSource': 'tmdb', 'externalId': '9', 'type': 'tvshow'}))!
              .url,
          'https://www.themoviedb.org/tv/9');
      expect(
          providerLink(item({'externalSource': 'tmdb', 'externalId': '9', 'type': 'tvshow', 'isAnime': true}))!
              .url,
          'https://www.themoviedb.org/tv/9');
      expect(providerLink(item({'externalSource': 'tmdb'})), isNull);
    });

    test('rawg: slug-id и search-фолбэк, slug с диакритикой', () {
      final game = item({
        'type': 'game',
        'title': 'Pokémon Sword',
        'externalSource': 'rawg',
        'externalId': '1234',
      });
      expect(providerLink(game)!.url, 'https://rawg.io/games/pokemon-sword-1234');
      final gameNoId = item({
        'type': 'game',
        'title': 'Elden Ring',
        'externalSource': 'rawg',
      });
      expect(providerLink(gameNoId)!.url,
          'https://rawg.io/search?q=${Uri.encodeComponent('Elden Ring')}');
    });

    test('lib-источники: mangadex/ranobelib/mangalib/animelib/slashlib', () {
      expect(
          providerLink(item({'externalSource': 'mangadex', 'externalId': 'a1'}))!.url,
          'https://mangadex.org/title/a1');
      expect(
          providerLink(item({'externalSource': 'ranobelib', 'externalId': 'r1'}))!.url,
          'https://ranobelib.me/ru/r1');
      expect(
          providerLink(item({'externalSource': 'mangalib', 'externalId': 'm1'}))!.url,
          'https://mangalib.me/ru/m1');
      // animelib — через buildAnimelibUrl: префиксы ru/anime/ зачищаются,
      // результат канонический (v5.animelib.org).
      expect(
          providerLink(item({'externalSource': 'animelib', 'externalId': '1234'}))!.url,
          'https://v5.animelib.org/ru/anime/1234');
      expect(
          providerLink(item({'externalSource': 'animelib', 'externalId': 'ru/anime/8231'}))!.url,
          'https://v5.animelib.org/ru/anime/8231');
      expect(
          providerLink(item({'externalSource': 'slashlib', 'externalId': 's1'}))!.url,
          'https://slashlib.me/ru/s1');
    });

    test('sociallib: anime → animelib, book → ranobelib, остальное → mangalib',
        () {
      expect(
          providerLink(item({
            'externalSource': 'sociallib',
            'externalId': '7',
            'type': 'tvshow',
            'isAnime': true,
          }))!.url,
          'https://v5.animelib.org/ru/anime/7');
      expect(
          providerLink(item({'externalSource': 'sociallib', 'externalId': '7', 'type': 'book'}))!
              .url,
          'https://ranobelib.me/ru/7');
      expect(
          providerLink(item({'externalSource': 'sociallib', 'externalId': '7', 'type': 'manga'}))!
              .url,
          'https://mangalib.me/ru/7');
      expect(providerLink(item({'externalSource': 'sociallib'})), isNull);
    });

    test('shikimori: animes/mangas', () {
      expect(
          providerLink(item({'externalSource': 'shikimori', 'externalId': '99', 'type': 'tvshow'}))!
              .url,
          'https://shikimori.io/animes/99');
      expect(
          providerLink(item({'externalSource': 'shikimori', 'externalId': '99', 'type': 'manga'}))!
              .url,
          'https://shikimori.io/mangas/99');
    });

    test('anilist: manga для манги/ранобэ, anime для аниме', () {
      expect(
          providerLink(item({'externalSource': 'anilist', 'externalId': '5', 'type': 'manga'}))!
              .url,
          'https://anilist.co/manga/5');
      expect(
          providerLink(item({
            'externalSource': 'anilist',
            'externalId': '5',
            'type': 'book',
            'format': 'light_novel',
          }))!.url,
          'https://anilist.co/manga/5');
      expect(
          providerLink(item({
            'externalSource': 'anilist',
            'externalId': '5',
            'type': 'tvshow',
            'isAnime': true,
          }))!.url,
          'https://anilist.co/anime/5');
      expect(
          providerLink(item({'externalSource': 'anilist', 'externalId': '5', 'type': 'book'}))!
              .url,
          'https://anilist.co/manga/5');
      expect(providerLink(item({'externalSource': 'anilist'})), isNull);
    });

    test('mal/jikan: id → /anime/<id>, без id → дом', () {
      expect(
          providerLink(item({'externalSource': 'myanimelist', 'externalId': '1'}))!.url,
          'https://myanimelist.net/anime/1');
      expect(providerLink(item({'externalSource': 'jikan'}))!.url,
          'https://myanimelist.net');
    });

    test('openlibrary: сырой id с ведущим слэшем и без', () {
      expect(
          providerLink(item({'externalSource': 'openlibrary', 'externalId': '/OL123M'}))!.url,
          'https://openlibrary.org/OL123M');
      expect(
          providerLink(item({'externalSource': 'openlibrary', 'externalId': 'OL123M'}))!.url,
          'https://openlibrary.org/OL123M');
    });

    test('igdb: только с id (slug от title)', () {
      expect(
          providerLink(item({
            'type': 'game',
            'title': 'The Witcher 3: Wild Hunt',
            'externalSource': 'igdb',
            'externalId': '100',
          }))!.url,
          'https://www.igdb.com/games/the-witcher-3-wild-hunt');
      expect(providerLink(item({'externalSource': 'igdb'})), isNull);
    });

    test('steam + неизвестный источник → null', () {
      expect(
          providerLink(item({'externalSource': 'steam', 'externalId': '570'}))!.url,
          'https://store.steampowered.com/app/570');
      expect(providerLink(item({'externalSource': 'unheard-source'})), isNull);
    });
  });

  group('tags', () {
    test('game: userPlatform приоритетен, пустой → platform', () {
      expect(tags(item({'type': 'game', 'userPlatform': ' Steam ', 'platform': 'PC'}), ruT),
          ['Игра', 'Steam']);
      expect(tags(item({'type': 'game', 'platform': 'PC'}), ruT), ['Игра', 'PC']);
      expect(tags(item({'type': 'game'}), ruT), ['Игра']);
    });

    test('book/manga: автор; movie: студия+режиссёр; tvshow: студия+сеть',
        () {
      expect(tags(item({'author': 'Толкин'}), ruT), ['Книга', 'Толкин']);
      expect(
          tags(
              item({
                'type': 'movie',
                'studio': 'Warner',
                'director': 'Villeneuve',
              }),
              ruT),
          ['Фильм', 'Warner', 'Villeneuve']);
      expect(
          tags(item({'type': 'tvshow', 'studio': 'MAPPA', 'network': 'BS11'}), ruT),
          ['Сериал', 'MAPPA', 'BS11']);
    });

    test('пустые строки отфильтрованы, дубликаты удалены', () {
      expect(tags(item({'type': 'movie', 'studio': '', 'director': ''}), ruT),
          ['Фильм']);
    });
  });

  group('releaseStatusLabel', () {
    test('game: raw-статусы', () {
      final t = item({
        'type': 'game',
        'releaseStatus': 'coming_soon',
      });
      expect(releaseStatusLabel(t, ruT), 'Скоро выйдет');
      expect(releaseStatusLabel(item({'type': 'game', 'releaseStatus': 'early_access'}), ruT),
          'Ранний доступ');
      expect(releaseStatusLabel(item({'type': 'game', 'releaseStatus': 'released'}), ruT),
          'Релиз');
    });

    test('game: будущая дата релиза → «Скоро выйдет»', () {
      expect(
          releaseStatusLabel(
              item({'type': 'game', 'releaseDate': '2099-01-01'}), ruT),
          'Скоро выйдет');
      expect(
          releaseStatusLabel(
              item({'type': 'game', 'releaseDate': '2001-01-01'}), ruT),
          'Релиз');
    });

    test('tv: точные raw-статусы', () {
      expect(releaseStatusLabel(item({'type': 'tvshow', 'releaseStatus': 'RELEASING'}), ruT),
          'Онгоинг');
      expect(releaseStatusLabel(item({'type': 'tvshow', 'releaseStatus': 'ENDED'}), ruT),
          'Завершён');
      expect(releaseStatusLabel(item({'type': 'tvshow', 'releaseStatus': 'UPCOMING'}), ruT),
          'Анонс');
      expect(releaseStatusLabel(item({'type': 'tvshow', 'releaseStatus': 'CANCELLED'}), ruT),
          'Отменён');
      expect(releaseStatusLabel(item({'type': 'tvshow', 'releaseStatus': 'HIATUS'}), ruT),
          'Приостановлен');
    });

    test('fallback по датам: end ≤ сегодня → завершён', () {
      expect(
          releaseStatusLabel(
              item({'type': 'tvshow', 'endDate': '2001-01-01'}), ruT),
          'Завершён');
      expect(
          releaseStatusLabel(
              item({'type': 'tvshow', 'releaseDate': '2099-01-01'}), ruT),
          'Анонс');
      expect(
          releaseStatusLabel(
              item({'type': 'tvshow', 'releaseDate': '2001-01-01'}), ruT),
          'Онгоинг');
      expect(releaseStatusLabel(item({'type': 'tvshow'}), ruT), '—');
    });
  });

  group('mangaChapterProgress / readProgress', () {
    test('mangaChapterProgress: не-манга → 0/null', () {
      final r = mangaChapterProgress(item({'type': 'book'}));
      expect(r.current, 0);
      expect(r.total, isNull);
      final m = mangaChapterProgress(
          item({'type': 'manga', 'currentChapter': 12, 'totalChapters': 100}));
      expect(m.current, 12);
      expect(m.total, 100);
    });

    test('readProgress: game → часы', () {
      final p = readProgress(item({'type': 'game', 'hoursPlayed': 42}), ruT)!;
      expect(p.current, 42);
      expect(p.total, isNull);
      expect(p.editable, isTrue);
      expect(p.label, 'Время в игре');
    });

    test('readProgress: book novel → главы, обычная → страницы', () {
      final novel = readProgress(
          item({
            'format': 'light_novel',
            'currentChapter': 3,
            'totalChapters': 8,
          }),
          ruT)!;
      expect(novel.current, 3);
      expect(novel.total, 8);
      expect(novel.label, 'Главы');
      final pages = readProgress(
          item({'currentPage': 100, 'totalPages': 300}), ruT)!;
      expect(pages.current, 100);
      expect(pages.total, 300);
      expect(pages.label, 'Страницы');
    });

    test('readProgress: manga → главы; tvshow → серии (не редактируется)',
        () {
      final manga = readProgress(
          item({'type': 'manga', 'currentChapter': 2, 'totalChapters': 9}), ruT)!;
      expect(manga.current, 2);
      expect(manga.total, 9);
      final tv = readProgress(
          item({
            'type': 'tvshow',
            'totalEpisodesWatched': 5,
            'totalEpisodesCount': 12,
          }),
          ruT)!;
      expect(tv.current, 5);
      expect(tv.total, 12);
      expect(tv.editable, isFalse);
      expect(tv.label, 'Серии');
    });

    test('readProgress: movie → null', () {
      expect(readProgress(item({'type': 'movie'}), ruT), isNull);
    });
  });

  group('original/romaji title', () {
    test('joinOriginalTitle: дедупликация и пропуск главного', () {
      expect(
          joinOriginalTitle(
              'Re:Zero', 'Re:ゼロ', 'Re:Zero kara Hajimeru Isekai Seikatsu'),
          'Re:ゼロ · Re:Zero kara Hajimeru Isekai Seikatsu');
      expect(joinOriginalTitle('Re:Zero', 'Re:Zero ', null), isNull);
      expect(joinOriginalTitle('X', 'Y', 'Y'), 'Y');
    });

    test('readOriginalTitle из MediaDetail', () {
      final d = MediaDetail.fromJson({
        ...baseJson(),
        'originalTitle': '鋼の錬金術師',
        'romajiTitle': 'Hagane no Renkinjutsushi',
      });
      expect(readOriginalTitle(d), '鋼の錬金術師 · Hagane no Renkinjutsushi');
    });

    test('readRomajiTitle: game/book → null, иначе trim', () {
      expect(readRomajiTitle(item({'type': 'game', 'romajiTitle': ' X '})), isNull);
      expect(readRomajiTitle(item({'type': 'manga', 'romajiTitle': ' X '})), 'X');
      expect(readRomajiTitle(item({'romajiTitle': '  '})), isNull);
    });
  });

  group('formatDate / formatReleaseDate', () {
    test('formatDate: пустое/битое → —; валидное → ru-формат', () {
      expect(formatDate(null, ruT), '—');
      expect(formatDate('', ruT), '—');
      expect(formatDate('not-a-date', ruT), '—');
      expect(formatDate('2024-05-05', ruT), contains('мая'));
      expect(formatDate('2024-05-05', enT), contains('May'));
    });

    test('formatReleaseDate: start с годовым фолбэком, end без него', () {
      // Только год: «2009 год» (ru) / «2009» (en).
      expect(formatReleaseDate(item({'releaseYear': 2009}), ruT), '2009 год');
      expect(formatReleaseDate(item({'releaseYear': 2009}), enT), '2009');
      // Полная дата.
      expect(formatReleaseDate(item({'releaseDate': '2024-05-05'}), ruT),
          contains('мая'));
      // End date: пусто → — (без годового фолбэка!).
      expect(
          formatReleaseDate(item({'releaseYear': 2009}), ruT,
              explicitDate: null, isEndDate: true),
          '—');
      // End date с датой.
      expect(
          formatReleaseDate(item({}), ruT,
              explicitDate: '2010-07-04', isEndDate: true),
          contains('июл'));
    });
  });

  test('orderOf: franchiseOrder ?? MAX_SAFE_INTEGER', () {
    expect(orderOf(item({'franchiseOrder': 3})), 3);
    expect(orderOf(item()), 9007199254740991);
  });

  group('buildEpisodes', () {
    TvSeason season(String? episodesData, int total, int current) =>
        TvSeason.fromJson({
          'id': 's1',
          'seasonNumber': 1,
          'title': 'Сезон 1',
          'totalEpisodes': total,
          'currentEpisode': current,
          'status': 1,
          'episodesData': episodesData,
          'tvShowId': 'tv1',
        });

    test('синхез без episodesData + watched-граница', () {
      final rows = buildEpisodes(season(null, 12, 3), ruT);
      // limit = min(total, max(watched, 200)) — все 12 строк.
      expect(rows, hasLength(12));
      expect(rows[0].number, 1);
      expect(rows[0].watched, isTrue);
      expect(rows[2].title, 'Серия 3');
      expect(rows[2].watched, isTrue);
      expect(rows[3].watched, isFalse);
      expect(rows[0].id, 's1:1');
    });

    test('episodesData мержится: title/airDate/description', () {
      final rows = buildEpisodes(
          season(
              '[{"number":2,"title":"Сигнал","airDate":"2024-01-02","description":"d2"}]',
              3,
              3),
          ruT);
      expect(rows[1].title, 'СSignal'.replaceFirst('СSignal', 'Сигнал'));
      expect(rows[1].airDate, '2024-01-02');
      expect(rows[1].description, 'd2');
      // Без данных — фолбэк на сезон.
      expect(rows[0].title, 'Серия 1');
      expect(rows[0].airDate, isNull);
      expect(rows[0].description, isNull);
    });

    test('total = max(totalEpisodes, parsed.length); битый JSON игнорируется',
        () {
      final rows = buildEpisodes(
          season('[{"number":1},{"number":2},{"number":3},{"number":4}]', 2, 4),
          ruT);
      expect(rows, hasLength(4));
      final broken = buildEpisodes(season('не-json{', 2, 2), ruT);
      expect(broken, hasLength(2));
    });

    test('cap 200: не-просмотренный хвост 5000 серий → 200 строк', () {
      final rows = buildEpisodes(season(null, 5000, 3), ruT);
      expect(rows, hasLength(maxEpisodesPerSeason));
      // Просмотренные строки cap не режет: watched 250 > 200 → 250 строк.
      final watched = buildEpisodes(season(null, 5000, 250), ruT);
      expect(watched, hasLength(250));
    });
  });

  test('relatedStatusColors: все 5 статусов', () {
    expect(relatedStatusColors(MediaStatus.completed).background,
        const Color(0xFF228B57));
    expect(relatedStatusColors(MediaStatus.inProgress).background,
        const Color(0xFF2563EB));
    expect(relatedStatusColors(MediaStatus.onHold).background,
        const Color(0xFFD97706));
    expect(relatedStatusColors(MediaStatus.dropped).background,
        const Color(0xFFB92B42));
    expect(relatedStatusColors(MediaStatus.planned).background,
        const Color(0xFF2A3040));
  });

  group('formatMediaDisplayType / formatRelationType / currentFormatLabel',
      () {
    test('formatMediaDisplayType: game/book/форматы/фолбэки', () {
      expect(formatMediaDisplayType('game', null, ruT), 'Игра');
      expect(formatMediaDisplayType('book', null, enT), 'Book');
      expect(formatMediaDisplayType('anime', 'TV', ruT), 'Сериал');
      expect(formatMediaDisplayType('anime', 'OVA', ruT), 'OVA');
      expect(formatMediaDisplayType('manga', null, ruT), 'Манга');
      expect(formatMediaDisplayType('movie', null, ruT), 'Фильм');
      expect(formatMediaDisplayType('anime', null, ruT), 'Сериал');
    });

    test('formatRelationType: все ключи + other', () {
      expect(formatRelationType('SEQUEL', ruT), 'Сиквел');
      expect(formatRelationType('ADAPTATION', ruT), 'Адаптация');
      expect(formatRelationType('WHATEVER', ruT), 'Связанное');
      expect(formatRelationType(null, ruT), 'Связанное');
    });

    test('currentFormatLabel: tvshow-detail → tv, movie → фильм, manga → манга',
        () {
      expect(currentFormatLabel(item({'type': 'movie'}), ruT), 'Фильм');
      expect(currentFormatLabel(item({'type': 'manga'}), ruT), 'Манга');
      expect(currentFormatLabel(item({'type': 'book'}), ruT), 'book');
      expect(currentFormatLabel(item({'type': 'game'}), ruT), 'game');
      final tv = MediaDetail.fromJson({
        ...baseJson({'type': 'tvshow'}),
        'seasons': [],
      });
      expect(currentFormatLabel(tv, ruT), 'Сериал');
    });
  });

  group('specRows', () {
    test('book novel: главы + тома; обычная книга: страницы', () {
      final novel = specRows(
          item({
            'format': 'light_novel',
            'totalChapters': 24,
            'totalVolumes': 4,
            'genres': ['Фэнтези'],
          }),
          ruT);
      final labels = novel.map((r) => r.label).toList();
      expect(labels, contains('Главы'));
      expect(labels, contains('Тома'));
      expect(novel.firstWhere((r) => r.label == 'Тома').value, '4');
      final pages = specRows(
          item({'totalPages': 500, 'genres': ['Фэнтези']}), ruT);
      expect(pages.firstWhere((r) => r.label == 'Страницы').value, '500 стр.');
    });

    test('movie: продолжительность + студия + ромадзи только у аниме', () {
      final rows = specRows(
          item({
            'type': 'movie',
            'durationMinutes': 126,
            'studio': 'Warner',
            'genres': ['Драма'],
          }),
          ruT);
      expect(rows.firstWhere((r) => r.label == 'Хронометраж').value,
          '126 мин.');
      expect(rows.firstWhere((r) => r.label == 'Студия').value, 'Warner');
      final animeTv = specRows(
          item({
            'type': 'tvshow',
            'isAnime': true,
            'romajiTitle': 'Shingeki',
            'genres': [],
          }),
          ruT);
      expect(
          animeTv.any((r) => r.label == 'Название на ромадзи'), isTrue);
    });

    test('источник + lineage: importSource отличается → строка показывается',
        () {
      final rows = specRows(
          item({
            'externalSource': 'shikimori',
            'importSource': 'anilist',
          }),
          ruT);
      final sourceRow = rows.last;
      expect(sourceRow.label, 'Источник данных');
      expect(sourceRow.importSource, 'anilist');
      // Совпадающий importSource скрыт.
      final same = specRows(
          item({'externalSource': 'shikimori', 'importSource': 'Shikimori'}),
          ruT);
      expect(same.last.importSource, isNull);
    });

    test('жанры: строка-JSON и запятые нормализуются, пустые → —', () {
      final rows = specRows(
          item({'genres': '["Фэнтези","Драма"]'}), ruT);
      final genreRow = rows.firstWhere((r) => r.label == 'Жанры');
      expect(genreRow.badges, ['Фэнтези', 'Драма']);
      final empty = specRows(item(), ruT);
      expect(empty.firstWhere((r) => r.label == 'Жанры').value, '—');
    });
  });
}
