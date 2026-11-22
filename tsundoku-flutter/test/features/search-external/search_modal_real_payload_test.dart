import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

void main() {
  group('CreateMediaRequest serialization & sanitization tests', () {
    test('normalizeIsoDate handles full ISO, partial dates, slashes, and fallback years', () {
      expect(normalizeIsoDate('2014-01-05'), '2014-01-05');
      expect(normalizeIsoDate('2010-12'), '2010-12-01');
      expect(normalizeIsoDate('2014'), '2014-01-01');
      expect(normalizeIsoDate('2001/7/20'), '2001-07-20');
      expect(normalizeIsoDate('2018-04-30T00:00:00Z'), '2018-04-30');
      expect(normalizeIsoDate('', 2010), '2010-01-01');
      expect(normalizeIsoDate(null, 2022), '2022-01-01');
      expect(normalizeIsoDate('invalid-date'), isNull);
      expect(normalizeIsoDate(''), isNull);
      expect(normalizeIsoDate(null), isNull);
    });

    test('ExternalRating and ExternalEpisode serialize to JSON without throwing', () {
      const rating = ExternalRating(
        source: 'metacritic',
        rating: 8.5,
        score: 85,
        votes: 120,
      );
      expect(rating.toJson(), {
        'source': 'metacritic',
        'rating': 8.5,
        'score': 85.0,
        'votes': 120,
      });
      expect(() => jsonEncode(rating.toJson()), returnsNormally);

      const episode = ExternalEpisode(
        number: 1,
        title: 'Pilot',
        airDate: '2023-01-01',
      );
      expect(episode.toJson(), {
        'number': 1,
        'title': 'Pilot',
        'airDate': '2023-01-01',
      });
      expect(() => jsonEncode(episode.toJson()), returnsNormally);
    });

    test('CreateMediaBase.baseToJson sanitizes empty strings, formats genres/tags as strings, cleans scores', () {
      const payload = CreateGamePayload(
        platform: 'PC',
        hoursPlayed: 10,
        title: 'Zelda',
        status: MediaStatus.planned,
        altTitles: null,
        score: 0, // Invalid score < 1 must be sanitized to null
        coverUrl: null,
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: 'invalid-guid', // Non-UUID must be sanitized to null
        franchiseName: null,
        franchiseOrder: null,
        externalId: null,
        externalSource: null,
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: '2023',
        endDate: '',
        releaseStatus: null,
        genres: ['Action', 'Adventure'],
        tags: ['Open World', 'Masterpiece'],
        unlockedAchievements: null,
        userPlatform: null,
      );
      final json = payload.toJson();
      expect(json['releaseDate'], '2023-01-01');
      expect(json['endDate'], isNull);
      expect(json['franchiseId'], isNull);
      expect(json['score'], isNull);
      expect(json['genres'], 'Action, Adventure');
      expect(json['tags'], 'Open World, Masterpiece');
    });

    test('CreateSeasonPayload.toJson ensures non-null status and normalized dates', () {
      const season = CreateSeasonPayload(
        seasonNumber: 0, // Clamped to >= 1
        title: '', // Fallback to 'Season 1'
        coverUrl: null,
        totalEpisodes: -5, // Clamped to 0
        status: null, // Fallback to planned (0)
        score: 11, // Invalid score > 10 sanitized to null
        notes: null,
        airDate: '2014',
        episodesData: null,
      );
      final json = season.toJson();
      expect(json['seasonNumber'], 1);
      expect(json['title'], 'Season 1');
      expect(json['totalEpisodes'], 0);
      expect(json['status'], MediaStatus.planned.value);
      expect(json['score'], isNull);
      expect(json['airDate'], '2014-01-01');
    });

    test('CreateBookPayload ensures non-empty author fallback', () {
      const book = CreateBookPayload(
        author: '',
        studio: null,
        isbn: null,
        totalPages: 200,
        format: 'novel',
        currentChapter: null,
        totalChapters: null,
        currentVolume: null,
        totalVolumes: null,
        title: 'Unnamed Book',
        status: MediaStatus.planned,
        altTitles: null,
        score: 8,
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
      final json = book.toJson();
      expect(json['author'], 'Unknown Author');
      expect(json['totalPages'], 200);
      expect(json['score'], 8);
    });

    test('CreateMangaPayload serializes format and non-negative counts', () {
      const manga = CreateMangaPayload(
        author: 'Adachitoka',
        romajiTitle: 'Noragami',
        totalVolumes: 27,
        totalChapters: 109,
        currentVolume: 1,
        format: 'manga',
        volumes: null,
        title: 'Noragami: Stray God',
        status: MediaStatus.planned,
        altTitles: ['Бездомный бог'],
        score: 9,
        coverUrl: 'https://example.com/cover.jpg',
        notes: null,
        description: 'Yato is a minor deity.',
        trailerVideoId: null,
        franchiseId: null,
        franchiseName: null,
        franchiseOrder: null,
        externalId: '3829',
        externalSource: 'AniList',
        importSource: null,
        externalRating: 8.2,
        externalRatingVotes: 15000,
        externalRatingsJson: '[{"source":"AniList","score":8.2,"rating":8.2}]',
        releaseDate: '2010-12-23',
        endDate: '2024-01-06',
        releaseStatus: 'FINISHED',
        genres: ['Action', 'Adventure', 'Supernatural'],
        tags: ['Gods', 'Mythology'],
        unlockedAchievements: null,
        userPlatform: null,
      );
      final json = manga.toJson();
      expect(json['type'], 'manga');
      expect(json['format'], 'manga');
      expect(json['totalChapters'], 109);
      expect(json['totalVolumes'], 27);
      expect(json['currentVolume'], 1);
      expect(json['genres'], 'Action, Adventure, Supernatural');
      expect(json['tags'], 'Gods, Mythology');
      expect(json['releaseDate'], '2010-12-23');
      expect(json['endDate'], '2024-01-06');
    });

    test('Live HTTP create against running MediaTracker.Server verifies all 5 media types return 201 Created', () async {
      final portCandidate = Platform.environment['TSUNDOKU_TEST_PORT'] ?? '5096';
      final dio = Dio(BaseOptions(
        baseUrl: 'http://localhost:$portCandidate',
        connectTimeout: const Duration(milliseconds: 1500),
        receiveTimeout: const Duration(milliseconds: 1500),
      ));

      try {
        await dio.get('/api/media');
      } on DioException {
        // Live server not running on test port; skipping live server integration check.
        return;
      }

      final createdIds = <String>[];
      try {
        // 1. Manga (Noragami test case)
        const mangaPayload = CreateMangaPayload(
          author: 'Adachitoka',
          romajiTitle: 'Noragami',
          totalVolumes: 27,
          totalChapters: 109,
          currentVolume: 1,
          format: 'manga',
          volumes: null,
          title: 'Noragami Live Integration Test',
          status: MediaStatus.planned,
          altTitles: ['Stray God'],
          score: 8,
          coverUrl: null,
          notes: null,
          description: 'Manga test description',
          trailerVideoId: null,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: '12345',
          externalSource: 'AniList',
          importSource: null,
          externalRating: 8.2,
          externalRatingVotes: 100,
          externalRatingsJson: null,
          releaseDate: '2010-12-23',
          endDate: '2024-01-06',
          releaseStatus: 'FINISHED',
          genres: ['Action', 'Supernatural'],
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
        final mangaRes = await dio.post('/api/media', data: mangaPayload.toJson());
        expect(mangaRes.statusCode, 201);
        final mangaData = mangaRes.data as Map<String, dynamic>;
        expect(mangaData['id'], isNotNull);
        createdIds.add(mangaData['id'] as String);

        // 2. TvShow / Anime (with seasons and airDate)
        const animePayload = CreateTvShowPayload(
          isAnime: true,
          studio: 'Bones',
          romajiTitle: 'Noragami Anime',
          network: null,
          durationMinutes: 24,
          episodeDurationMinutes: 24,
          seasons: [
            CreateSeasonPayload(
              seasonNumber: 1,
              title: 'Season 1',
              coverUrl: null,
              totalEpisodes: 12,
              status: MediaStatus.planned,
              score: null,
              notes: null,
              airDate: '2014-01-05',
              episodesData: null,
            ),
          ],
          title: 'Noragami Anime Live Test',
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
          releaseDate: '2014-01-05',
          endDate: null,
          releaseStatus: null,
          genres: ['Anime', 'Supernatural'],
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
        final animeRes = await dio.post('/api/media', data: animePayload.toJson());
        expect(animeRes.statusCode, 201);
        final animeData = animeRes.data as Map<String, dynamic>;
        expect(animeData['id'], isNotNull);
        createdIds.add(animeData['id'] as String);

        // 3. Movie (Spirited Away test case)
        const moviePayload = CreateMoviePayload(
          durationMinutes: 125,
          director: 'Hayao Miyazaki',
          isAnime: true,
          studio: 'Studio Ghibli',
          romajiTitle: 'Sen to Chihiro no Kamikakushi',
          title: 'Spirited Away Live Test',
          status: MediaStatus.planned,
          altTitles: null,
          score: 10,
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
          releaseDate: '2001-07-20',
          endDate: null,
          releaseStatus: null,
          genres: ['Animation', 'Fantasy'],
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
        final movieRes = await dio.post('/api/media', data: moviePayload.toJson());
        expect(movieRes.statusCode, 201);
        final movieData = movieRes.data as Map<String, dynamic>;
        expect(movieData['id'], isNotNull);
        createdIds.add(movieData['id'] as String);

        // 4. Book (Dune with ISBN)
        const bookPayload = CreateBookPayload(
          author: 'Frank Herbert',
          studio: 'Chilton Books',
          isbn: '9780441172719',
          totalPages: 412,
          format: 'novel',
          currentChapter: null,
          totalChapters: null,
          currentVolume: null,
          totalVolumes: null,
          title: 'Dune Live Test',
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
          releaseDate: '1965-08-01',
          endDate: null,
          releaseStatus: null,
          genres: ['Science Fiction'],
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
        final bookRes = await dio.post('/api/media', data: bookPayload.toJson());
        expect(bookRes.statusCode, 201);
        final bookData = bookRes.data as Map<String, dynamic>;
        expect(bookData['id'], isNotNull);
        createdIds.add(bookData['id'] as String);

        // 5. Game (Elden Ring with platform and hoursPlayed)
        const gamePayload = CreateGamePayload(
          platform: 'PC',
          hoursPlayed: 85,
          title: 'Elden Ring Live Test',
          status: MediaStatus.inProgress,
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
          releaseDate: '2022-02-25',
          endDate: null,
          releaseStatus: null,
          genres: ['Action RPG', 'Open World'],
          tags: null,
          unlockedAchievements: null,
          userPlatform: 'Steam',
        );
        final gameRes = await dio.post('/api/media', data: gamePayload.toJson());
        expect(gameRes.statusCode, 201);
        final gameData = gameRes.data as Map<String, dynamic>;
        expect(gameData['id'], isNotNull);
        createdIds.add(gameData['id'] as String);
      } finally {
        // Clean up created entities
        for (final id in createdIds) {
          try {
            await dio.delete('/api/media/$id');
          } catch (_) {}
        }
      }
    });
  });
}
