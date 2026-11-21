import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/index.dart' show MediaItem;
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/related_matching.dart';

/// Тесты `relatedMatching.test.ts` (vitest-кейсы 1-в-1): нормализация,
/// strip movie-маркеров, каскад матчинга без кросс-матча TV vs Movie,
/// findMatchingLocal.
void main() {
  MediaItem mediaItem(Map<String, Object?> json) =>
      MediaItem.fromJson({
        'id': 'id',
        'type': 'tvshow',
        'title': '',
        'status': 2,
        'createdAt': '2024-01-01T00:00:00Z',
        ...json,
      });

  RelatedEntry rel(Map<String, Object?> json) => RelatedEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        originalTitle: json['originalTitle'] as String?,
        romajiTitle: json['romajiTitle'] as String?,
        type: json['type'] as String? ?? 'anime',
        format: json['format'] as String?,
      );

  test('normalizes titles properly', () {
    expect(normalizeTitle('Violet Evergarden: the Movie'),
        'violetevergardenthemovie');
    expect(normalizeTitle('Вайолет Эвергарден. Фильм'), 'вайолетэвергарденфильм');
    expect(normalizeTitle('劇場版 ヴァイオレット・エヴァーガーデン'),
        '劇場版ヴァイオレットエヴァーガーデン');
  });

  test('strips movie markers properly', () {
    expect(stripMovieMarker('Violet Evergarden: the Movie'),
        'Violet Evergarden:');
    expect(stripMovieMarker('Violet Evergarden Movie'), 'Violet Evergarden');
    expect(stripMovieMarker('Вайолет Эвергарден. Фильм'), 'Вайолет Эвергарден.');
  });

  test('matches local entities accurately without cross-matching TV vs Movie',
      () {
    final violetTvShow = mediaItem({
      'id': 'uuid-series',
      'type': 'tvshow',
      'title': 'Вайолет Эвергарден',
      'status': 2,
      'score': 10,
      'isAnime': true,
      'romajiTitle': 'Violet Evergarden',
      'externalId': '33352',
      'externalSource': 'Shikimori',
      'studio': 'Kyoto Animation',
      'totalEpisodesCount': 13,
      'totalEpisodesWatched': 13,
      'seasonsCount': 1,
    });

    final violetMovie = mediaItem({
      'id': 'uuid-movie',
      'type': 'movie',
      'title': 'Вайолет Эвергарден. Фильм',
      'status': 2,
      'score': 9,
      'isAnime': true,
      'romajiTitle': 'Violet Evergarden Movie',
      'externalId': '37987',
      'externalSource': 'Shikimori',
      'durationMinutes': 140,
    });

    final relMovie = rel({
      'id': '103047',
      'title': 'Violet Evergarden: the Movie',
      'romajiTitle': 'Violet Evergarden Movie',
      'originalTitle': '劇場版 ヴァイオレット・エヴァーガーデン',
      'type': 'anime',
      'format': 'MOVIE',
    });

    final relSeries = rel({
      'id': '21827',
      'title': 'Violet Evergarden',
      'romajiTitle': 'Violet Evergarden',
      'originalTitle': 'ヴァイオレット・エヴァーガーデン',
      'type': 'anime',
      'format': 'TV',
    });

    final relGaiden = rel({
      'id': '109121',
      'title': 'Violet Evergarden: Eternity and the Auto Memory Doll',
      'romajiTitle': 'Violet Evergarden Gaiden: Eien to Jidou Shuki Ningyou',
      'type': 'anime',
      'format': 'MOVIE',
    });

    expect(isRelatedMatch(relMovie, violetMovie), isTrue);
    expect(isRelatedMatch(relMovie, violetTvShow), isFalse);

    expect(isRelatedMatch(relSeries, violetTvShow), isTrue);
    expect(isRelatedMatch(relSeries, violetMovie), isFalse);

    final allMedia = <MediaItem>[violetTvShow, violetMovie];
    expect(findMatchingLocal(relMovie, allMedia)?.id, violetMovie.id);
    expect(findMatchingLocal(relSeries, allMedia)?.id, violetTvShow.id);
    expect(findMatchingLocal(relGaiden, allMedia), isNull);
  });

  test('каскад: external ID — самый сильный матч', () {
    final item = mediaItem({
      'title': 'Совсем другое название',
      'externalId': '777',
    });
    final entry = rel({'id': '777', 'title': 'Whatever'});
    expect(isRelatedMatch(entry, item), isTrue);
  });

  test('romaji у game/book не участвует в матче (readItemRomaji)', () {
    final game = mediaItem({
      'id': 'g1',
      'type': 'game',
      'title': 'Hollow Knight',
      'romajiTitle': 'Violet Evergarden',
    });
    final entry = rel({'id': 'x1', 'title': 'ZZZ', 'romajiTitle': 'Violet Evergarden'});
    // Ромадзи источника совпадает с romajiTitle игры, но game исключён из
    // ромадзи-ветки и кросс-матч названий не сходится.
    expect(isRelatedMatch(entry, game), isFalse);
  });

  test('пустая/отсутствующая библиотека → null', () {
    final entry = rel({'id': '1', 'title': 'X'});
    expect(findMatchingLocal(entry, null), isNull);
    expect(findMatchingLocal(entry, <MediaItem>[]), isNull);
  });
}
