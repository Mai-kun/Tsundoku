import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';

void main() {
  test('emptyCategoryDraft — дефолты 1-в-1 с moduleTypes.ts', () {
    final draft = CategoryDraft.empty();
    expect(draft.platform, '');
    expect(draft.hoursPlayed, '');
    expect(draft.author, '');
    expect(draft.bookFormat, 'book');
    expect(draft.totalPages, '');
    expect(draft.totalChapters, '');
    expect(draft.bookTotalVolumes, '');
    expect(draft.currentVolume, '');
    expect(draft.durationMinutes, '');
    expect(draft.isAnime, isFalse);
    expect(draft.studio, '');
    expect(draft.network, '');
    expect(draft.seasons, isEmpty);
    // Каждый вызов — новый объект (Svelte: каждый вызов владеет в $state).
    expect(identical(CategoryDraft.empty(), CategoryDraft.empty()), isFalse);
  });

  test('copyWith — частичные правки', () {
    final draft = CategoryDraft.empty();
    final updated = draft.copyWith(
      platform: 'PC',
      hoursPlayed: '12',
      isAnime: true,
      seasons: [
        const SeasonDraft(
            seasonNumber: '1', title: 'S1', totalEpisodes: '12'),
      ],
    );
    expect(updated.platform, 'PC');
    expect(updated.hoursPlayed, '12');
    expect(updated.isAnime, isTrue);
    expect(updated.bookFormat, 'book'); // не изменённое поле сохранилось
    expect(updated.seasons.single.totalEpisodes, '12');
  });

  test('SeasonDraft — equality по полям формы', () {
    expect(
      const SeasonDraft(seasonNumber: '1', title: 'x', totalEpisodes: '9'),
      const SeasonDraft(seasonNumber: '1', title: 'x', totalEpisodes: '9'),
    );
    expect(
      const SeasonDraft(seasonNumber: '1', title: 'x', totalEpisodes: '9'),
      isNot(const SeasonDraft(
          seasonNumber: '1', title: 'x', totalEpisodes: '10')),
    );
  });

  test('kEditMediaTypes — порядок как в EDIT_MEDIA_TYPES', () {
    expect(kEditMediaTypes,
        ['game', 'movie', 'tvshow', 'book', 'manga']);
  });
}
