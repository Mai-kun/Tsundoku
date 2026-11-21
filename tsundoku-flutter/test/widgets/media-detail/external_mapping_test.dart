import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/external_mapping.dart';

/// Тесты `externalMapping.test.ts`: server relation → view-model (1-в-1
/// vitest-кейсы).
void main() {
  Map<String, Object?> media([Map<String, Object?> overrides = const {}]) => {
        'externalId': '42',
        'externalSource': 'AniList',
        'title': 'Berserk',
        'originalTitle': 'ベルセルク',
        'romajiTitle': 'Berserk',
        'coverUrl': 'large.jpg',
        'description': 'Dark fantasy.',
        'releaseYear': 1997,
        'releaseDate': '1997-04-06',
        'endDate': '2004',
        'releaseStatus': 'RELEASED',
        'format': 'TV',
        'runtimeMinutes': 24,
        'type': 'anime',
        'author': 'Kentaro Miura',
        'studio': 'OLM',
        'totalCount': 25,
        'rating': 8.2,
        'platform': null,
        ...overrides,
      };

  ExternalRelation relation([Map<String, Object?> overrides = const {},
      String relationType = 'PREQUEL']) =>
      ExternalRelation.fromJson({
        'relationType': relationType,
        'media': media(overrides),
      });

  test('survives raw relation type untouched', () {
    final entry = toRelatedEntry(relation());
    expect(entry.rawRelationType, 'PREQUEL');
    expect(entry.id, '42');
    expect(entry.type, 'anime');
  });

  test('handles known and missing ratings correctly', () {
    final entry = toRelatedEntry(relation());
    expect(entry.score, 8.2);
    expect(entry.ratings, isNotNull);
    expect(entry.ratings!.length, 1);
    expect(entry.ratings!.first.source, 'AniList');
    expect(entry.ratings!.first.score, 8.2);

    final unrated = toRelatedEntry(relation({'rating': null}));
    expect(unrated.score, isNull);
    expect(unrated.ratings, isNull);
  });

  test('normalises dates and counts', () {
    final entry = toRelatedEntry(relation());
    expect(entry.releaseDate, '1997-04-06');
    expect(entry.endDate, '2004');
    expect(entry.year, 1997);
    expect(entry.episodes, 25);
  });

  test('leaves missing year null', () {
    final entry = toRelatedEntry(relation({
      'releaseYear': null,
      'releaseDate': null,
    }));
    expect(entry.year, isNull);
    expect(entry.releaseDate, isNull);
  });

  test('preserves format', () {
    expect(toRelatedEntry(relation()).format, 'TV');
    expect(
        toRelatedEntry(relation({'type': 'manga', 'format': 'MANGA'}, 'ADAPTATION'))
            .format,
        'MANGA');
  });

  test('falls back to default title when blank', () {
    expect(toRelatedEntry(relation({'title': ''})).title, 'Title');
  });
}
