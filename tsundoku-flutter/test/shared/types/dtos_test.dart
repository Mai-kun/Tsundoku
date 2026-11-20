import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';

void main() {
  group('Create*-payload\'ы (полный цикл сериализации на сервер)', () {
    test('CreateGamePayload: точный payload 1-в-1', () {
      const p = CreateGamePayload(
        platform: 'PC',
        hoursPlayed: 12,
        title: 'Hades',
        status: MediaStatus.inProgress,
        altTitles: null,
        score: 9,
        coverUrl: 'https://cdn.example/hades.jpg',
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        externalId: '123',
        externalSource: 'RAWG',
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: null,
        endDate: null,
        releaseStatus: null,
        genres: ['Roguelike'],
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );
      expect(p.toJson(), {
        'type': 'game',
        'title': 'Hades',
        'status': 1,
        'altTitles': null,
        'score': 9,
        'coverUrl': 'https://cdn.example/hades.jpg',
        'notes': null,
        'description': null,
        'trailerVideoId': null,
        'franchiseId': null,
        'franchiseName': null,
        'franchiseOrder': null,
        'externalId': '123',
        'externalSource': 'RAWG',
        'importSource': null,
        'externalRating': null,
        'externalRatingVotes': null,
        'externalRatingsJson': null,
        'releaseDate': null,
        'endDate': null,
        'releaseStatus': null,
        'genres': ['Roguelike'],
        'tags': null,
        'unlockedAchievements': null,
        'userPlatform': null,
        'platform': 'PC',
        'hoursPlayed': 12,
      });
    });

    test('CreateBookPayload: book-специфика поверх базы', () {
      const p = CreateBookPayload(
        author: 'Frank Herbert',
        studio: null,
        isbn: '978-0441013593',
        totalPages: 412,
        format: null,
        currentChapter: 3,
        totalChapters: null,
        currentVolume: null,
        totalVolumes: null,
        title: 'Dune',
        status: MediaStatus.planned,
        altTitles: null,
        score: null,
        coverUrl: null,
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        externalId: null,
        externalSource: null,
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: null,
        endDate: null,
        releaseStatus: null,
        genres: null,
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );
      expect(p.toJson()['type'], 'book');
      expect(p.toJson()['author'], 'Frank Herbert');
      expect(p.toJson()['totalPages'], 412);
      expect(p.toJson()['status'], 0);
    });

    test('CreateMangaPayload с вложенными volumes', () {
      const p = CreateMangaPayload(
        author: 'Автор',
        romajiTitle: 'Berserk',
        totalVolumes: 40,
        totalChapters: 364,
        currentVolume: 1,
        volumes: [
          CreateVolumePayload(
            volumeNumber: 1,
            title: 'Том 1',
            coverUrl: null,
            totalPages: 224,
            currentPage: 0,
            totalChapters: 8,
            currentChapter: 0,
            status: MediaStatus.planned,
            score: null,
            notes: null,
            releaseDate: null,
          ),
        ],
        title: 'Berserk',
        status: MediaStatus.inProgress,
        altTitles: null,
        score: null,
        coverUrl: null,
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        externalId: null,
        externalSource: null,
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: null,
        endDate: null,
        releaseStatus: null,
        genres: null,
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );
      final json = p.toJson();
      expect(json['type'], 'manga');
      final volumes = json['volumes'] as List<Map<String, dynamic>>;
      expect(volumes.single, {
        'volumeNumber': 1, 'title': 'Том 1', 'coverUrl': null,
        'totalPages': 224, 'currentPage': 0, 'totalChapters': 8,
        'currentChapter': 0, 'status': 0, 'score': null, 'notes': null,
        'releaseDate': null,
      });
    });

    test('CreateMoviePayload и CreateTvShowPayload', () {
      const movie = CreateMoviePayload(
        durationMinutes: 146,
        director: 'Denis Villeneuve',
        isAnime: false,
        studio: 'Legendary',
        romajiTitle: null,
        title: 'Dune',
        status: MediaStatus.completed,
        altTitles: null,
        score: 9,
        coverUrl: null,
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        externalId: null,
        externalSource: null,
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: null,
        endDate: null,
        releaseStatus: null,
        genres: null,
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );
      expect(movie.toJson()['type'], 'movie');
      expect(movie.toJson()['status'], 2);
      expect(movie.toJson()['durationMinutes'], 146);

      const tv = CreateTvShowPayload(
        isAnime: true,
        studio: 'Madhouse',
        romajiTitle: null,
        network: null,
        durationMinutes: null,
        episodeDurationMinutes: 24,
        seasons: [
          CreateSeasonPayload(
            seasonNumber: 1,
            title: 'Season 1',
            coverUrl: null,
            totalEpisodes: 12,
            status: null,
            score: null,
            notes: null,
            airDate: null,
            episodesData: '[]',
          ),
        ],
        title: 'Frieren',
        status: MediaStatus.inProgress,
        altTitles: null,
        score: null,
        coverUrl: null,
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        externalId: null,
        externalSource: null,
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: null,
        endDate: null,
        releaseStatus: null,
        genres: null,
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );
      final tvJson = tv.toJson();
      expect(tvJson['type'], 'tvshow');
      expect(tvJson['episodeDurationMinutes'], 24);
      expect((tvJson['seasons'] as List).single['totalEpisodes'], 12);
      expect((tvJson['seasons'] as List).single['episodesData'], '[]');
    });

    test('UpdateMediaPayload: clear-флаги и nullable-семантика 1-в-1', () {
      const p = UpdateMediaPayload(
        title: null,
        altTitles: ['New alt'],
        score: null,
        clearScore: true,
        detailedScoreJson: null,
        clearDetailedScore: false,
        status: MediaStatus.dropped,
        notes: null,
        quotesJson: null,
        coverUrl: null,
        startedAt: null,
        finishedAt: null,
        lastActivityAt: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        author: null,
        isbn: null,
        format: null,
        romajiTitle: null,
        totalVolumes: null,
        currentVolume: null,
        totalChapters: null,
        currentChapter: null,
        totalPages: null,
        currentPage: null,
        translatedSynopsis: null,
        translationLanguage: null,
        platform: null,
        userPlatform: null,
        clearUserPlatform: true,
        clearWatchedOn: false,
        clearDropReason: false,
        dropReason: 'Не зашло',
        dropNotes: null,
        watchedOn: null,
        releaseYear: null,
        genres: 'RPG, Indie',
        tags: null,
        unlockedAchievements: null,
        relatedMediaJson: null,
        relatedSource: null,
        achievementsJson: null,
        recommendationsJson: null,
        isCustomEdited: true,
      );
      expect(p.toJson(), {
        'title': null,
        'altTitles': ['New alt'],
        'score': null,
        'clearScore': true,
        'detailedScoreJson': null,
        'clearDetailedScore': false,
        'status': 4,
        'notes': null,
        'quotesJson': null,
        'coverUrl': null,
        'startedAt': null,
        'finishedAt': null,
        'lastActivityAt': null,
        'franchiseId': null,
        'franchiseName': null,
        'franchiseOrder': null,
        'author': null,
        'isbn': null,
        'format': null,
        'romajiTitle': null,
        'totalVolumes': null,
        'currentVolume': null,
        'totalChapters': null,
        'currentChapter': null,
        'totalPages': null,
        'currentPage': null,
        'translatedSynopsis': null,
        'translationLanguage': null,
        'platform': null,
        'userPlatform': null,
        'clearUserPlatform': true,
        'clearWatchedOn': false,
        'clearDropReason': false,
        'dropReason': 'Не зашло',
        'dropNotes': null,
        'watchedOn': null,
        'releaseYear': null,
        'genres': 'RPG, Indie',
        'tags': null,
        'unlockedAchievements': null,
        'relatedMediaJson': null,
        'relatedSource': null,
        'achievementsJson': null,
        'recommendationsJson': null,
        'isCustomEdited': true,
      });
    });

    test('UpdateVolumePayload сериализует nullable status', () {
      const p = UpdateVolumePayload(
        title: null,
        coverUrl: null,
        totalPages: null,
        currentPage: 50,
        totalChapters: null,
        currentChapter: 4,
        status: MediaStatus.onHold,
        score: null,
        notes: null,
      );
      expect(p.toJson()['status'], 3);
      expect(p.toJson()['currentPage'], 50);
    });
  });

  group('Списки и smart-запросы', () {
    test('CreateListPayload == UpdateListPayload (typedef)', () {
      const UpdateListPayload p = CreateListPayload(
        name: '2026 backlog',
        description: null,
        icon: '📚',
        color: '#473bb8',
        smartQueryJson: null,
      );
      expect(p.toJson(), {
        'name': '2026 backlog', 'description': null, 'icon': '📚',
        'color': '#473bb8', 'smartQueryJson': null,
      });
    });

    test('SmartListQuery toJson полный', () {
      const q = SmartListQuery(
        categories: ['game', 'book'],
        statuses: [0, 1],
        minScore: 7,
        maxScore: 10,
        onlyUnrated: false,
        minExternalRating: 4.0,
        genres: ['RPG'],
        releaseYearFrom: 2020,
        releaseYearTo: null,
        maxDurationMinutes: 120,
        maxEpisodes: 24,
        maxPages: 400,
        maxChapters: null,
        creatorContains: 'Пулемёт',
        releaseStatus: 'FINISHED',
        sortBy: 'createdAt',
        sortOrder: 'desc',
        limit: 100,
      );
      expect(q.toJson()['minExternalRating'], 4.0);
      expect(q.toJson()['statuses'], [0, 1]);
      expect(q.toJson()['releaseStatus'], 'FINISHED');
    });
  });

  group('Импорт-пейлоады', () {
    test('SteamImportPayload / AniList / MangaLib toJson', () {
      const steam = SteamImportPayload(
        steamId: '76561198',
        profileUrl: null,
        steamApiKey: 'KEY',
        skipDuplicates: true,
        targetListId: null,
        newListName: 'Steam backlog',
        minPlaytimeMinutes: 60,
        syncAchievements: false,
      );
      expect(steam.toJson()['minPlaytimeMinutes'], 60);
      expect(steam.toJson()['steamApiKey'], 'KEY');

      const ani = AniListProfilePayload(
        username: 'user',
        createList: true,
        targetListId: null,
        newListName: null,
        skipDuplicates: null,
      );
      expect(ani.toJson()['username'], 'user');
      expect(ani.toJson()['createList'], true);

      const manga = MangaLibProfilePayload(
        profileUrlOrId: '12345',
        siteIds: [1, 4],
        bearerToken: 'tok',
        statusIds: [1, 2, 3],
        includeCustomFolders: true,
        skipDuplicates: false,
        targetListId: null,
        newListName: null,
      );
      expect(manga.toJson()['siteIds'], [1, 4]);
      expect(manga.toJson()['statusIds'], [1, 2, 3]);
    });

    test('ImportResultDto парсится', () {
      final r = ImportResultDto.fromJson({
        'totalFound': 50, 'importedCount': 48, 'skippedDuplicates': 2,
        'targetListId': 'l1', 'targetListName': 'Backlog',
        'skippedTitles': ['Dup 1'], 'dumpUrl': null, 'dumpFileName': null,
      });
      expect(r.importedCount, 48);
      expect(r.skippedTitles, ['Dup 1']);
    });
  });

  group('Read-only DTO', () {
    test('PendingMatchItemDto с candidates и duplicate', () {
      final p = PendingMatchItemDto.fromJson({
        'id': 'pm1', 'title': 'Монстер', 'romajiTitle': null,
        'originalTitle': 'モンスター', 'altTitles': ['Monster'],
        'type': 'manga', 'isAnime': null, 'releaseYear': 1994,
        'author': 'Урасава', 'currentProgress': 10, 'totalCount': null,
        'countryOfOrigin': 'JP', 'mangaFormat': null,
        'candidates': [
          {
            'externalId': 'c1', 'externalSource': 'MangaLib', 'title': 'Monster',
            'originalTitle': null, 'romajiTitle': null, 'coverUrl': null,
            'description': null, 'trailerVideoId': null, 'releaseYear': null,
            'releaseDate': null, 'endDate': null, 'releaseStatus': null,
            'format': null, 'runtimeMinutes': null, 'type': 'manga',
            'author': null, 'studio': null, 'isbn': null, 'covers': null,
            'totalCount': 18, 'chapters': null, 'volumes': null,
            'mangaFormat': null, 'countryOfOrigin': null, 'platform': null,
            'rating': null, 'ratingVotes': null, 'ratings': null,
            'episodes': null, 'genres': null, 'tags': null, 'synonyms': null,
          }
        ],
        'duplicate': null,
      });
      expect(p.candidates.single.externalId, 'c1');
      expect(p.duplicate, isNull);
    });

    test('PendingMatchItemDto: duplicate-conflict ветка', () {
      final p = PendingMatchItemDto.fromJson({
        'id': 'pm2', 'title': 'Dupe', 'type': 'game',
        'candidates': <Map<String, dynamic>>[],
        'duplicate': {
          'conflictType': 'exact',
          'existingMediaId': 'm-9',
          'existingTitle': 'Same Game',
          'incomingSource': 'RAWG',
          'incomingExternalId': '777',
          'incomingTitle': 'Same Game',
        },
      });
      expect(p.duplicate?.existingMediaId, 'm-9');
      expect(p.duplicate?.conflictType, 'exact');
    });

    test('CustomListSummary и CustomListDetail', () {
      final s = CustomListSummary.fromJson({
        'id': 'l1', 'name': 'Done 2026', 'description': null, 'icon': null,
        'color': null, 'itemsCount': 12, 'updatedAt': '2026-11-01T00:00:00Z',
        'previewCovers': ['a.jpg', null], 'isSmart': false,
        'smartQueryJson': null,
      });
      expect(s.previewCovers, ['a.jpg', null]);
      expect(s.itemsCount, 12);

      final d = CustomListDetail.fromJson({
        'id': 'l1', 'name': 'Done 2026', 'description': null, 'icon': null,
        'color': null, 'createdAt': '2026-01-01T00:00:00Z', 'items': [],
        'isSmart': true, 'smartQueryJson': '{"minScore":8}',
      });
      expect(d.items, isEmpty);
      expect(d.isSmart, isTrue);
    });

    test('SourceInfo со isProxied', () {
      final s = SourceInfo.fromJson({
        'id': 'steam', 'name': 'Steam', 'description': 'Games',
        'mediaTypes': ['game'], 'requiresApiKey': false,
        'optionalApiKey': true, 'isConfigured': true, 'hasKey': false,
        'maskedKey': null, 'isEnabled': true, 'isScraper': false,
        'isProxied': true,
      });
      expect(s.optionalApiKey, isTrue);
      expect(s.isProxied, isTrue);
    });

    test('Calendar DTO: kind по wire, unknown → ArgumentError', () {
      final item = CalendarItemDto.fromJson({
        'mediaId': 'm1', 'title': 'Ongoing', 'type': 'tvshow',
        'coverUrl': null, 'currentProgress': 3, 'totalCount': 12,
        'kind': 'auto_refresh', 'details': null, 'episodeNumber': null,
        'seasonNumber': 2, 'isAnime': true,
      });
      expect(item.kind, CalendarEventKind.autoRefresh);

      final day = CalendarDayDto.fromJson({
        'date': '2026-11-25', 'items': [
          {'mediaId': 'm2', 'title': 'Air', 'type': 'manga', 'coverUrl': null,
           'currentProgress': null, 'totalCount': null, 'kind': 'air_date',
           'details': null, 'episodeNumber': 5, 'seasonNumber': null,
           'isAnime': null},
        ],
      });
      final schedule = CalendarScheduleDto.fromJson({
        'from': '2026-11-20', 'to': '2026-12-20', 'days': [
          {'date': '2026-11-25', 'items': []},
        ],
      });
      expect(day.items.single.kind, CalendarEventKind.airDate);
      expect(schedule.days.single.date, '2026-11-25');

      expect(
        () => CalendarItemDto.fromJson({
          'mediaId': 'm3', 'title': 'x', 'type': 'book', 'coverUrl': null,
          'currentProgress': null, 'totalCount': null, 'kind': 'party',
          'details': null, 'episodeNumber': null, 'seasonNumber': null,
        }),
        throwsArgumentError,
      );
    });

    test('BacklogDeadlineDto (air_date-ветка)', () {
      final b = BacklogDeadlineDto.fromJson({
        'mediaId': 'm1', 'title': 'Ongoing', 'type': 'tvshow',
        'coverUrl': null, 'kind': 'air_date', 'deadlineDate': '2026-12-01',
        'daysLeft': 10, 'episodeNumber': 8, 'seasonNumber': 3,
        'behindCount': 4, 'blockerTitle': null, 'blockerProgress': null,
        'blockerTotalCount': null,
      });
      expect(b.kind, CalendarEventKind.airDate);
      expect(b.daysLeft, 10);
      expect(b.behindCount, 4);
    });

    test('GoalDto и CreateGoalPayload', () {
      final g = GoalDto.fromJson({
        'id': 'g1', 'title': '50 книг', 'description': null, 'icon': '📚',
        'year': 2026, 'targetCount': 50, 'currentCount': 12,
        'isCompleted': false, 'category': 'book', 'smartQueryJson': null,
        'completedItems': [],
      });
      expect(g.year, 2026);
      expect(g.category, 'book');

      const cg = CreateGoalPayload(
        title: '50 книг', description: null, icon: null, year: 2027,
        targetCount: 50, category: null, smartQueryJson: null,
      );
      expect(cg.toJson()['year'], 2027);
      expect(cg.toJson()['targetCount'], 50);
    });

    test('ApiTokenSummary / CreateApiTokenResponse / ConnectionTestResult / ApiRateLimitStatus', () {
      final t = ApiTokenSummary.fromJson({
        'id': 't1', 'name': 'CLI', 'tokenPrefix': 'tsd_ab12',
        'createdAt': '2026-11-01T00:00:00Z', 'lastUsedAt': null,
        'expiresAt': null,
      });
      expect(t.tokenPrefix, 'tsd_ab12');

      final ct = CreateApiTokenResponse.fromJson({
        'id': 't1', 'name': 'CLI', 'tokenPrefix': 'tsd_ab12',
        'rawToken': 'tsd_secret',
      });
      expect(ct.rawToken, 'tsd_secret');

      final conn = ConnectionTestResult.fromJson({
        'success': true, 'latencyMs': 45, 'message': 'ok',
      });
      expect(conn.latencyMs, 45);

      final rl = ApiRateLimitStatus.fromJson({
        'provider': 'AniList', 'remaining': 25, 'limit': 90,
        'resetSecondsRemaining': 60, 'updatedAt': '2026-11-21T00:00:00Z',
      });
      expect(rl.remaining, 25);
    });
  });
}
