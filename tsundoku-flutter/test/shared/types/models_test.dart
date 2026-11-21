import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// Полный цикл: реальный (по форме openapi MediaListDto) payload → модель →
/// обратный JSON → равенство.
void main() {
  final gameJson = <String, dynamic>{
    'id': '7c1e2b3a-0001-4000-8000-000000000001',
    'type': 'game',
    'title': 'Hollow Knight',
    'status': 2,
    'syncStatus': 0,
    'score': 9,
    'startedAt': '2026-01-10T00:00:00Z',
    'finishedAt': '2026-03-01T00:00:00Z',
    'lastActivityAt': '2026-03-01T12:00:00Z',
    'dropReason': null,
    'dropNotes': null,
    'coverUrl': 'https://cdn.example/hk.jpg',
    'createdAt': '2026-01-10T00:00:00Z',
    'updatedAt': '2026-03-02T00:00:00Z',
    'franchiseId': null,
    'franchiseName': null,
    'franchiseOrder': null,
    'externalId': '367520',
    'externalSource': 'RAWG',
    'importSource': null,
    'externalRating': 4.7,
    'externalRatingVotes': 1200,
    'translationLanguage': null,
    'releaseDate': '2017-02-24T00:00:00Z',
    'releaseYear': 2017,
    'watchedOn': 'Steam',
    'endDate': null,
    'releaseStatus': 'Released',
    'originalLanguage': 'en',
    'countryOfOrigin': null,
    'durationMinutes': null,
    'genres': ['Metroidvania', 'Indie'],
    'tags': 'platformer, souls-like',
    'userPlatform': 'PC',
    'format': null,
    'nextAutoRefreshAt': null,
    'autoRefreshIntervalDays': 7,
    'lastAutoRefreshedAt': null,
    'platform': 'PC',
    'hoursPlayed': 45,
    'author': null,
    'currentPage': null,
    'totalPages': null,
    'currentChapter': null,
    'totalChapters': null,
    'currentVolume': null,
    'totalVolumes': null,
    'isbn': null,
    'studio': 'Team Cherry',
    'romajiTitle': null,
    'mangaFormat': null,
    'isAnime': null,
    'network': null,
    'totalEpisodesCount': null,
    'totalEpisodesWatched': null,
    'seasonsCount': null,
    'episodeDurationMinutes': null,
    'director': null,
  };

  group('MediaItem (плоский MediaListDto)', () {
    test('fromJson парсит все поля 1:1', () {
      final m = MediaItem.fromJson(gameJson);
      expect(m.type, MediaType.game);
      expect(m.status, MediaStatus.completed);
      expect(m.syncStatus, SyncStatus.ready);
      expect(m.score, 9);
      expect(m.externalRating, 4.7);
      expect(m.platform, 'PC');
      expect(m.hoursPlayed, 45);
      expect(m.studio, 'Team Cherry');
      // genres массивом:
      expect(m.genres, ['Metroidvania', 'Indie']);
    });

    test('genres строкой: JSON-массив распаковывается, запятые нормализуются',
        () {
      // Источники шлют JSON-массив строкой — split(',') ломал бы элементы
      // (1-в-1 с parseGenresList из detailFormatters.ts).
      final jsonArr = MediaItem.fromJson(<String, dynamic>{
        ...gameJson,
        'genres': '["Фэнтези","Драма"]',
        'tags': 'платформер, souls-like',
      });
      expect(jsonArr.genres, ['Фэнтези', 'Драма']);
      expect(jsonArr.tags, ['платформер', 'souls-like']);
      // Не-JSON строка → прежний split(',')-путь.
      final plain = MediaItem.fromJson(<String, dynamic>{
        ...gameJson,
        'genres': 'Action, RPG',
      });
      expect(plain.genres, ['Action', 'RPG']);
    });

    test('toJson(fromJson(json)) == json в канонической форме (нормализация)', () {
      final m = MediaItem.fromJson(gameJson);
      // string[]|string нормализуется в список (решение #3), поэтому сравнение
      // с канонической формой payload'а + идемпотентность повторного парсинга.
      final canonical = <String, dynamic>{...gameJson,
        'genres': ['Metroidvania', 'Indie'],
        'tags': ['platformer', 'souls-like'],
      };
      expect(m.toJson(), canonical);
      // Идемпотентность: fromJson(toJson(m)) == m.
      expect(MediaItem.fromJson(m.toJson()).toJson(), canonical);
    });

    test('tags строкой нормализуется в List (решение #3)', () {
      final m = MediaItem.fromJson(gameJson);
      expect(m.tags, ['platformer', 'souls-like']);
    });

    test('genres строкой тоже нормализуется (string[] | string)', () {
      final m = MediaItem.fromJson({...gameJson, 'genres': ' RPG , Action '});
      expect(m.genres, ['RPG', 'Action']);
    });

    test('nullable-поля сохраняются при обратной сериализации', () {
      final m = MediaItem.fromJson(gameJson);
      expect(m.toJson()['franchiseId'], isNull);
      expect(m.toJson()['currentChapter'], isNull);
    });

    test('var-поля tvshow-варианта парсятся из того же payload', () {
      final m = MediaItem.fromJson({
        ...gameJson,
        'type': 'tvshow',
        'isAnime': true,
        'network': 'HBO',
        'totalEpisodesCount': 24,
        'totalEpisodesWatched': 10,
        'seasonsCount': 3,
        'episodeDurationMinutes': 45,
        'director': null,
        'platform': null,
        'hoursPlayed': null,
        'studio': 'Madhouse',
      });
      expect(m.type, MediaType.tvshow);
      expect(m.isAnime, isTrue);
      expect(m.totalEpisodesWatched, 10);
      expect(m.seasonsCount, 3);
      expect(m.episodeDurationMinutes, 45);
    });
  });

  group('MediaDetail (detail-DTO поверх list-DTO)', () {
    final detailJson = <String, dynamic>{
      ...gameJson,
      'notes': 'Планирую второй заход.',
      'linkedSourcesJson': '[]',
      'linkedSources': [
        {
          'source': 'steam',
          'externalId': '367520',
          'url': 'https://store.steampowered.com/app/367520',
          'isPrimary': true,
          'title': 'Steam page',
          'providedFields': ['coverUrl', 'description'],
        }
      ],
      'detailedScoreJson': null,
      'quotesJson': null,
      'description': 'A hauntingMetroidvania.',
      'trailerVideoId': 'abc123',
      'cast': [
        {'name': 'Alice', 'character': 'Hornet', 'photoUrl': null,
         'characterRole': 'SUPPORTING', 'characterImageUrl': null,
         'voiceActorName': 'Мика Канай', 'voiceActorImageUrl': null},
      ],
      'originalTitle': 'Hollow Knight',
      'altTitles': ['空洞騎士'],
      'staffJson': null,
      'staff': [
        {'name': 'William Pellen', 'role': 'Designer', 'imageUrl': null},
      ],
      'creatorImageUrl': 'https://cdn.example/studio.png',
      'externalRatingsJson': null,
      'translatedSynopsis': null,
      'unlockedAchievements': 'Protective',
      'relatedMediaJson': null,
      'relatedSource': null,
      'achievementsJson': null,
      'recommendationsJson': null,
      'recommendationsUpdatedAt': null,
      'pendingMatchesJson': null,
      'pendingMatches': null,
      'recommendations': [
        {'id': 'r1', 'title': 'Celeste', 'coverUrl': null, 'rating': 4.5,
         'source': 'TMDb'},
      ],
      'isCustomEdited': false,
      'covers': [
        {'id': 'c1', 'thumbUrl': 'https://cdn.example/t.jpg',
         'originalUrl': 'https://cdn.example/o.jpg', 'source': 'steam',
         'sourceUrl': 'https://cdn.example/src.jpg',
         'addedAt': '2026-02-01T00:00:00Z'},
      ],
      'attachments': [
        {'id': 'a1', 'fileName': 'save.dat', 'fileSizeBytes': 1024,
         'contentType': 'application/octet-stream',
         'addedAt': '2026-02-02T00:00:00Z'},
      ],
      'gallery': [
        {'id': 'g1', 'thumbUrl': 'https://cdn.example/gt.jpg',
         'originalUrl': 'https://cdn.example/go.jpg', 'title': 'Boss fight',
         'addedAt': '2026-02-03T00:00:00Z'},
      ],
    };

    test('detail-поля парсятся 1:1', () {
      final d = MediaDetail.fromJson(detailJson);
      expect(d.notes, 'Планирую второй заход.');
      expect(d.linkedSources?.single.isPrimary, isTrue);
      expect(d.linkedSources?.single.providedFields, ['coverUrl', 'description']);
      expect(d.cast?.single.voiceActorName, 'Мика Канай');
      expect(d.altTitles, ['空洞騎士']);
      expect(d.isCustomEdited, isFalse);
      expect(d.covers?.single.thumbUrl, 'https://cdn.example/t.jpg');
      expect(d.attachments?.single.fileSizeBytes, 1024);
      expect(d.gallery?.single.title, 'Boss fight');
      expect(d.recommendations?.single.rating, 4.5);
      // Базовые поля тоже на месте:
      expect(d.hoursPlayed, 45);
    });

    test('LinkedSource round-trip toJson', () {
      final d = MediaDetail.fromJson(detailJson);
      expect(d.linkedSources?.single.toJson(),
          (detailJson['linkedSources'] as List).first);
    });

    test('isTvShowDetail / isMangaDetail (1-в-1 предикаты)', () {
      final game = MediaItem.fromJson(gameJson);
      expect(isTvShowDetail(game), isFalse);
      expect(isMangaDetail(game), isFalse);

      final tv = MediaDetail.fromJson({
        ...gameJson,
        'type': 'tvshow',
        'seasons': [
          {
            'id': 's1', 'seasonNumber': 1, 'title': 'S1', 'coverUrl': null,
            'currentEpisode': 2, 'totalEpisodes': 12, 'status': 1,
            'score': null, 'notes': null, 'airDate': null,
            'episodesData': null, 'tvShowId': gameJson['id'],
          }
        ],
      });
      expect(isTvShowDetail(tv), isTrue);
      expect(tv.seasons?.single.currentEpisode, 2);
      // Manga-предикат не требует volumes (1-в-1 с TS).
      final manga = MediaDetail.fromJson({
        ...gameJson,
        'type': 'manga',
        'currentChapter': 5,
        'totalChapters': 100,
        'currentVolume': 1,
        'author': 'Автор',
      });
      expect(isMangaDetail(manga), isTrue);
      expect(isTvShowDetail(manga), isFalse);
    });

    test('MangaVolume round-trip', () {
      const volumeJson = {
        'id': 'v1', 'volumeNumber': 2, 'title': 'Том 2',
        'coverUrl': 'https://cdn.example/v2.jpg', 'currentPage': 30,
        'totalPages': 192, 'currentChapter': 12, 'totalChapters': 45,
        'status': 1, 'score': 8, 'notes': 'Начал', 'releaseDate': null,
        'mangaId': 'm1',
      };
      final v = MangaVolume.fromJson(volumeJson);
      expect(v.status, MediaStatus.inProgress);
      expect(v.toJson(), volumeJson);
    });

    test('TvSeason round-trip', () {
      const seasonJson = {
        'id': 's1', 'seasonNumber': 1, 'title': 'Season 1',
        'coverUrl': null, 'currentEpisode': 3, 'totalEpisodes': 12,
        'status': 0, 'score': null, 'notes': null,
        'airDate': '2020-04-05T00:00:00Z', 'episodesData': '[]',
        'tvShowId': 't1',
      };
      final s = TvSeason.fromJson(seasonJson);
      expect(s.status, MediaStatus.planned);
      expect(s.toJson(), seasonJson);
    });

    test('HistoryEvent round-trip', () {
      const eventJson = {
        'id': 'e1', 'mediaId': 'm1', 'type': 'ProgressChanged',
        'oldValue': '5', 'newValue': '10',
        'createdAt': '2026-11-01T00:00:00Z', 'title': 'Book title',
      };
      final e = HistoryEvent.fromJson(eventJson);
      expect(e.type, HistoryEventType.progressChanged);
      expect(e.toJson(), eventJson);
    });

    test('HistoryEvent: title null после удаления медиа', () {
      final e = HistoryEvent.fromJson({
        'id': 'e2', 'mediaId': 'm1', 'type': 'Deleted', 'oldValue': null,
        'newValue': null, 'createdAt': '2026-11-01T00:00:00Z', 'title': null,
      });
      expect(e.title, isNull);
      expect(e.toJson()['title'], isNull);
    });
  });

  group('AdvancedStats', () {
    test('scoreDistribution: строковые JSON-ключи → Map<int, double>', () {
      final stats = AdvancedStats.fromJson({
        'totalTitles': 100, 'completedTitles': 40,
        'completionRatePercent': 40.0, 'totalHours': 1200.5,
        'totalDays': 50.0, 'gameHours': 400.0, 'movieHours': 200.0,
        'seriesHours': 300.0, 'animeHours': 100.0, 'bookHours': 150.5,
        'mangaHours': 50.0, 'totalPagesRead': 12000,
        'totalChaptersRead': 900, 'totalEpisodesWatched': 700,
        'seriesEpisodesWatched': 300, 'animeEpisodesWatched': 400,
        'averageScore': 7.2, 'scoreDistribution': {'0': 1, '5': 12, '10': 8},
        'averageScoreByType': {'game': 8.1, 'book': 6.5},
        'currentStreakDays': 4,
        'monthlyCompletions': [{'monthYear': '2026-10', 'count': 7}],
        'topGenres': [{'genre': 'RPG', 'count': 30, 'percentage': 30.0}],
        'topGenresByType': {'game': [{'genre': 'RPG', 'count': 20, 'percentage': 20.0}]},
        'dailyActivity': {'2026-11-20': 2.5, '2026-11-21': 1},
      });
      expect(stats.scoreDistribution.keys, [0, 5, 10]);
      expect(stats.scoreDistribution[5], 12.0);
      expect(stats.averageScoreByType['game'], 8.1);
      expect(stats.monthlyCompletions.single.count, 7);
      expect(stats.topGenresByType['game']?.single.genre, 'RPG');
      expect(stats.dailyActivity['2026-11-21'], 1.0);
    });
  });

  group('ExternalMedia (поиск, включая anime)', () {
    test('парсинг + anime-тип + isDirectUrl', () {
      final m = ExternalMedia.fromJson({
        'externalId': '1', 'externalSource': 'AniList', 'title': 'Frieren',
        'originalTitle': '葬送のフリーレン', 'romajiTitle': 'Sousou no Frieren',
        'coverUrl': 'https://cdn.example/f.jpg', 'description': null,
        'trailerVideoId': null, 'releaseYear': 2023,
        'releaseDate': '2023-09-29T00:00:00Z', 'endDate': null,
        'releaseStatus': 'FINISHED', 'format': 'TV', 'runtimeMinutes': 24,
        'type': 'anime', 'author': null, 'studio': 'Madhouse', 'isbn': null,
        'covers': null, 'totalCount': 28, 'chapters': null, 'volumes': null,
        'mangaFormat': null, 'countryOfOrigin': 'JP', 'platform': null,
        'rating': 9.1, 'ratingVotes': 5000,
        'ratings': [
          {'source': 'AniList', 'rating': 9.1, 'score': null, 'votes': 5000},
        ],
        'episodes': [
          {'number': 1, 'title': 'The Journey\'s End', 'airDate': '2023-09-29T00:00:00Z'},
        ],
        'genres': 'Fantasy, Adventure',
        'tags': null, 'synonyms': ['Frieren'], 'isDirectUrl': true,
      });
      expect(m.type, 'anime');
      expect(knownSearchMediaTypes.contains(m.type), isTrue);
      expect(m.rating, 9.1);
      expect(m.ratings?.single.source, 'AniList');
      expect(m.episodes?.single.number, 1);
      // genres строкой нормализуется и здесь:
      expect(m.genres, ['Fantasy', 'Adventure']);
      expect(m.isDirectUrl, isTrue);
    });
  });

  group('MediaFilters (query-параметры)', () {
    test('пустые фильтры → пустой query', () {
      expect(const MediaFilters().toQueryParameters(), <String, dynamic>{});
    });

    test('все фильтры сериализуются как в API', () {
      const f = MediaFilters(
        type: MediaType.book,
        status: MediaStatus.inProgress,
        isAnime: false,
        subId: 'comics',
        search: 'дюна',
        sortBy: SortBy.createdAt,
        sortOrder: SortOrder.desc,
        limit: 50,
        offset: 100,
      );
      expect(f.toQueryParameters(), <String, dynamic>{
        'type': 'book',
        'status': 1,
        'isAnime': false,
        'subId': 'comics',
        'search': 'дюна',
        'sortBy': 'createdAt',
        'sortOrder': 'desc',
        'limit': 50,
        'offset': 100,
      });
    });

    test('пустой search не попадает в query (как в Svelte-клиенте)', () {
      const f = MediaFilters(search: '');
      expect(f.toQueryParameters().containsKey('search'), isFalse);
    });
  });

  group('Storage', () {
    test('StorageSettings парсит mode и isFirstRunSetupRequired', () {
      final s = StorageSettings.fromJson({
        'mode': 'portable', 'defaultDirectory': '/data', 
        'portableDirectory': '/usb/tsundoku', 'customPath': null,
        'isFirstRunSetupRequired': true,
      });
      expect(s.mode, StorageMode.portable);
      expect(s.customPath, isNull);
      expect(s.isFirstRunSetupRequired, isTrue);
    });

    test('StorageRequest toJson round-trip (payload запроса)', () {
      const r = StorageRequest(
        mode: StorageMode.custom,
        customPath: '/mnt/library',
        migrateExistingData: true,
      );
      expect(r.toJson(), {
        'mode': 'custom', 'customPath': '/mnt/library', 'migrateExistingData': true,
      });
    });

    test('неизвестный mode — ArgumentError', () {
      expect(
        () => StorageSettings.fromJson({
          'mode': 'cloud', 'defaultDirectory': '', 'portableDirectory': '',
          'customPath': null, 'isFirstRunSetupRequired': false,
        }),
        throwsArgumentError,
      );
    });
  });

  group('Offline / Search cache', () {
    test('OfflineDatabasesSummaryDto со вложенными БД', () {
      final d = OfflineDatabasesSummaryDto.fromJson({
        'databases': [
          {'name': 'AniList', 'fileName': 'anilist.db', 'type': 'anime',
           'totalTitles': 3000, 'fileSizeBytes': 999, 
           'lastModified': '2026-11-20T00:00:00Z', 'isActive': true,
           'sourceDumpFileName': 'dump.jsonl'},
        ],
        'totalIndexedTitles': 3000, 'offlineDirectoryPath': '/offline',
        'pendingDumps': ['x.json'],
      });
      expect(d.databases.single.sourceDumpFileName, 'dump.jsonl');
      expect(d.totalIndexedTitles, 3000);
      expect(d.pendingDumps, ['x.json']);
    });

    test('SearchCacheInfoDto парсится 1:1', () {
      final c = SearchCacheInfoDto.fromJson({
        'entryCount': 42, 'fileSizeBytes': 111111, 'imageFileCount': 20,
        'imageFileSizeBytes': 222222, 'databasePath': '/cache/search.db',
      });
      expect(c.entryCount, 42);
      expect(c.databasePath, '/cache/search.db');
    });
  });
}
