import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/index.dart' show SourceInfo;
import 'package:tsundoku_flutter/widgets/media-detail/rating_badges.dart';

/// Тесты `ratingBadges.test.ts` (vitest-кейсы 1-в-1) + TDD-сверхнабор
/// базовых поведений: score 0 → плейсхолдер, sociallib-зонт, выключенные
/// источники, includeMissing, fallback.
void main() {
  SourceInfo source(
    String id,
    String name,
    List<String> mediaTypes, {
    bool isEnabled = true,
  }) =>
      SourceInfo.fromJson({
        'id': id,
        'name': name,
        'description': '',
        'mediaTypes': mediaTypes,
        'requiresApiKey': false,
        'optionalApiKey': false,
        'isConfigured': true,
        'hasKey': false,
        'maskedKey': null,
        'isEnabled': isEnabled,
        'isScraper': false,
        'isProxied': null,
      });

  final mockSources = <SourceInfo>[
    source('openlibrary', 'OpenLibrary', ['book']),
    source('livelib', 'LiveLib', ['book']),
    source('anilist', 'AniList', ['anime', 'manga']),
    source('shikimori', 'Shikimori', ['anime', 'manga']),
  ];

  group('buildRatingBadges с linkedSources (vitest)', () {
    test('renders only linked sources and excludes unlinked ones', () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [
          const RawRating(source: 'LiveLib', rating: 8.4, votes: 120),
          const RawRating(source: 'AniList', rating: 7.5, votes: 300),
        ],
        category: 'book',
        availableSources: mockSources,
        linkedSources: const ['openlibrary', 'livelib'],
      ));

      final sources = badges.map((b) => b.source.toLowerCase()).toList();
      expect(sources, contains('livelib'));
      expect(sources, contains('openlibrary'));
      expect(sources, isNot(contains('anilist')));
      expect(sources, isNot(contains('shikimori')));

      final livelibBadge =
          badges.firstWhere((b) => b.source.toLowerCase() == 'livelib');
      expect(livelibBadge.score, 8.4);

      final openLibraryBadge =
          badges.firstWhere((b) => b.source.toLowerCase() == 'openlibrary');
      expect(openLibraryBadge.score, isNull);
    });

    test('renders no badges if no sources are linked', () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [const RawRating(source: 'AniList', rating: 8.0)],
        category: 'book',
        availableSources: mockSources,
        linkedSources: const [],
      ));

      expect(badges, isEmpty);
    });
  });

  group('buildRatingBadges: базовые поведения (TDD)', () {
    test('score 0 → плейсхолдер (queried), а не отсутствие источника', () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [const RawRating(source: 'AniList', rating: 0, queried: true)],
        category: 'anime',
        availableSources: mockSources,
        includeMissing: false,
      ));

      expect(badges.length, 1);
      expect(badges.first.source, 'AniList');
      expect(badges.first.score, isNull);
      expect(badges.first.queried, isTrue);
    });

    test('sociallib-зонт выбрасывается, per-site остаётся', () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [
          const RawRating(source: 'SocialLib', rating: 7.0),
          const RawRating(source: 'MangaLib', rating: 8.0),
        ],
        category: 'manga',
        availableSources: mockSources,
        includeMissing: false,
      ));

      expect(badges.length, 1);
      expect(badges.first.source, 'MangaLib');
    });

    test('выключенные источники выбрасываются целиком', () {
      final disabled = [
        ...mockSources,
        source('kitsu', 'Kitsu', ['manga'], isEnabled: false),
      ];
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [
          const RawRating(source: 'Kitsu', rating: 9.0),
          const RawRating(source: 'AniList', rating: 8.0),
        ],
        category: 'manga',
        availableSources: disabled,
        includeMissing: false,
      ));

      expect(badges.map((b) => b.source), ['AniList']);
    });

    test('дедуп по lowercase имени источника', () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [
          const RawRating(source: 'AniList', rating: 8.0),
          const RawRating(source: 'anilist', rating: 9.0),
        ],
        category: 'anime',
        availableSources: mockSources,
        includeMissing: false,
      ));

      expect(badges.length, 1);
      expect(badges.first.score, 8.0); // первый побеждает
    });

    test('fallback одиночного score — только при пустом ratings', () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: const [],
        fallback: const FallbackRating(source: 'Steam', score: 8.7, votes: 320),
        category: 'game',
        availableSources: const [],
        includeMissing: false,
      ));

      expect(badges.length, 1);
      expect(badges.first.source, 'Steam');
      expect(badges.first.score, 8.7);
      expect(badges.first.votes, 320);
    });

    test('includeMissing: ожидаемые источники получают пустые плейсхолдеры',
        () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: [const RawRating(source: 'AniList', rating: 8.0)],
        category: 'manga',
        availableSources: const [],
        // fallbackSources из kCategoryExpectedSources['manga'].
        includeMissing: true,
      ));

      final sources = badges.map((b) => b.source).toList();
      expect(sources, contains('AniList'));
      expect(sources, contains('MangaDex'));
      expect(sources, contains('MangaUpdates'));
      // У плейсхолдеров нет score.
      final mangaDex = badges.firstWhere((b) => b.source == 'MangaDex');
      expect(mangaDex.score, isNull);
    });

    test('availableSources ≠ [] → ожидаемые = включённые источники категории',
        () {
      final badges = buildRatingBadges(RatingBadgeInput(
        ratings: const [],
        category: 'book',
        availableSources: mockSources,
        includeMissing: true,
      ));

      expect(badges.map((b) => b.source), ['OpenLibrary', 'LiveLib']);
    });
  });
}
