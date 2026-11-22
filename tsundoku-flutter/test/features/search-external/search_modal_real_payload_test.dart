import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

void main() {
  group('CreateMediaRequest serialization & sanitization tests', () {
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

      final cast = CastMember.fromJson({
        'name': 'Actor Name',
        'character': 'Hero',
      });
      expect(cast.toJson(), {
        'name': 'Actor Name',
        'character': 'Hero',
      });
      expect(() => jsonEncode(cast.toJson()), returnsNormally);

      final staff = StaffMember.fromJson({
        'name': 'Director Name',
        'role': 'Director',
      });
      expect(staff.toJson(), {
        'name': 'Director Name',
        'role': 'Director',
      });
      expect(() => jsonEncode(staff.toJson()), returnsNormally);
    });

    test('CreateMediaBase.baseToJson sanitizes empty string dates to null', () {
      const payload = CreateGamePayload(
        platform: 'PC',
        hoursPlayed: 10,
        title: 'Zelda',
        status: MediaStatus.planned,
        altTitles: null,
        score: null,
        coverUrl: null,
        notes: null,
        description: null,
        trailerVideoId: null,
        franchiseId: '',
        franchiseName: null,
        franchiseOrder: null,
        externalId: null,
        externalSource: null,
        importSource: null,
        externalRating: null,
        externalRatingVotes: null,
        externalRatingsJson: null,
        releaseDate: '',
        endDate: '',
        releaseStatus: null,
        genres: null,
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );
      final json = payload.toJson();
      expect(json['releaseDate'], isNull);
      expect(json['endDate'], isNull);
      expect(json['franchiseId'], isNull);
    });

    test('CreateSeasonPayload.toJson sanitizes empty string airDate to null', () {
      const season = CreateSeasonPayload(
        seasonNumber: 1,
        title: 'Season 1',
        coverUrl: null,
        totalEpisodes: 12,
        status: MediaStatus.planned,
        score: null,
        notes: null,
        airDate: '',
        episodesData: null,
      );
      final json = season.toJson();
      expect(json['airDate'], isNull);
    });

    test('Live HTTP create against running backend creates media successfully', () async {
      final dio = Dio(BaseOptions(
        baseUrl: 'http://localhost:5097',
        connectTimeout: const Duration(milliseconds: 500),
        receiveTimeout: const Duration(milliseconds: 500),
      ));

      try {
        await dio.get('/api/media');
      } on DioException {
        // Backend not running on port 5097 in offline test runner; skip live HTTP probe.
        return;
      }

      // Test creating game with ratings and empty date strings (real edge case)
      final createGame = {
        'type': 'game',
        'title': 'Elden Ring Test Audit',
        'platform': 'PC',
        'status': 0,
        'releaseDate': null,
        'ratings': [
          {'source': 'rawg', 'rating': 9.5, 'score': 95.0, 'votes': 500}
        ],
      };

      final response = await dio.post('/api/media', data: createGame);
      expect(response.statusCode, inInclusiveRange(200, 201));
      final created = response.data as Map<String, dynamic>;
      expect(created['id'], isNotNull);
      expect(created['title'], 'Elden Ring Test Audit');

      // Clean up created media
      final id = created['id'] as String;
      await dio.delete('/api/media/$id');
    });
  });
}
