import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';

/// Smoke-тесты view-типов детальной страницы: конструирование всех классов,
/// wire-круговорот enum'ов.
void main() {
  test('ProgressInfo: все поля', () {
    const info = ProgressInfo(
        current: 3, total: 12, editable: true, label: 'Глава 3 из 12');
    expect(info.current, 3);
    expect(info.total, 12);
    expect(info.editable, isTrue);
    expect(info.label, 'Глава 3 из 12');
  });

  test('SpecRow: опциональные href/badges/importSource', () {
    const row = SpecRow(label: 'Студия', value: 'MAPPA');
    expect(row.href, isNull);
    expect(row.badges, isNull);
    const row2 = SpecRow(
        label: 'Жанры',
        value: '',
        badges: ['Экшен', 'Драма'],
        importSource: 'shikimori',
        href: 'https://example.com');
    expect(row2.badges, ['Экшен', 'Драма']);
    expect(row2.importSource, 'shikimori');
  });

  test('EpisodeRow', () {
    const row = EpisodeRow(
        id: 'e1',
        number: 7,
        title: 'Эпизод 7',
        airDate: '2024-05-01',
        description: null,
        watched: false);
    expect(row.number, 7);
    expect(row.watched, isFalse);
    expect(row.airDate, '2024-05-01');
  });

  test('NextUp', () {
    const n = NextUp(seasonId: 's2', seasonNumber: 2, episodeNumber: 1);
    expect(n.seasonId, 's2');
    expect(n.seasonNumber, 2);
    expect(n.episodeNumber, 1);
  });

  test('RecommendationItem', () {
    const r = RecommendationItem(
        id: 'm9',
        title: 'Frieren',
        coverUrl: null,
        rating: 9.2,
        source: 'anilist');
    expect(r.rating, 9.2);
    expect(r.coverUrl, isNull);
  });

  test('RelatedEntry: полный и минимальный конструктор', () {
    const minimal = RelatedEntry(id: 'r1', title: 'FMA', type: 'manga');
    expect(minimal.format, isNull);
    expect(minimal.localItem, isNull);
    const full = RelatedEntry(
      id: 'r2',
      title: 'FMA: Brotherhood',
      originalTitle: '鋼の錬金術師',
      coverUrl: '/media-assets/x/thumb.webp',
      bannerUrl: null,
      type: 'tvshow',
      format: 'tv',
      year: 2009,
      relationType: 'adaptation',
      rawRelationType: 'adaptation',
      score: 9.1,
      ratings: [RatingBadge(source: 'mal', score: 9.0, votes: 100, queried: true)],
      description: 'desc',
      trailerVideoId: 'abc',
      episodes: 64,
      chapters: null,
      volumes: 27,
      studio: 'Bones',
      author: null,
      romajiTitle: 'Hagane no Renkinjutsushi',
      duration: 24,
      releaseDate: '2009-04-05',
      endDate: '2010-07-04',
      releaseStatus: 'completed',
      externalSource: 'mal',
    );
    expect(full.ratings!.first.source, 'mal');
    expect(full.ratings!.first.queried, isTrue);
    expect(full.volumes, 27);
  });

  test('RatingBadge: queried дефолт false', () {
    const b = RatingBadge(source: 'tmdb', score: null);
    expect(b.queried, isFalse);
    expect(b.votes, isNull);
  });

  test('RelationGroup + TimelineEntry', () {
    const g = RelationGroup(
        id: 'g1', title: 'Адаптации', items: []);
    expect(g.items, isEmpty);
    const t = TimelineEntry(
        id: 't1',
        title: 'FMA',
        coverUrl: null,
        year: 2003,
        formatDisplay: 'Аниме-сериал',
        relationType: 'adaptation',
        isCurrent: false,
        rawItem: RelatedEntry(id: 'r1', title: 'FMA', type: 'anime'));
    expect(t.year, 2003);
    expect(t.rawItem!.id, 'r1');
  });

  test('SubTab/RelatedViewMode: wire round-trip', () {
    for (final v in SubTab.values) {
      expect(SubTab.fromWire(v.wire), v);
    }
    expect(SubTab.fromWire('episodes'), SubTab.episodes);
    expect(
        () => SubTab.fromWire('nope'), throwsArgumentError);
    for (final v in RelatedViewMode.values) {
      expect(RelatedViewMode.fromWire(v.wire), v);
    }
    expect(
        () => RelatedViewMode.fromWire('x'), throwsArgumentError);
  });

  test('RelatedEntry.localItem принимает MediaItem', () {
    final item = MediaItem.fromJson(const {
      'id': 'm1',
      'type': 'book',
      'title': 'Властелин колец',
      'status': 2,
      'createdAt': '2024-01-01T00:00:00Z',
    });
    const e = RelatedEntry(
        id: 'r3', title: 'LOTR', type: 'book', localItem: null);
    expect(e.localItem, isNull);
    final e2 = RelatedEntry(
        id: 'r4', title: 'LOTR', type: 'book', localItem: item);
    expect(e2.localItem!.id, 'm1');
  });
}
