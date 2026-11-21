import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/panels/related_preview_modal.dart';

/// Тесты `RelatedPreviewModal.svelte`: превью-постер, факт-строки,
/// статусы/добавление, описание, null-item.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpModal(
    WidgetTester tester, {
    RelatedEntry? item,
    List<RatingBadge> badges = const [],
    bool loading = false,
    bool adding = false,
    MediaStatus status = MediaStatus.planned,
    void Function(MediaStatus)? onStatusChange,
    void Function(MediaStatus)? onAdd,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      // Модалка: без scrollview-предка — ModalBarrier требует bounded height.
      child: MaterialApp(
        home: Material(
          child: RelatedPreviewModal(
            item: item,
            badges: badges,
            loading: loading,
            adding: adding,
            status: status,
            onStatusChange: onStatusChange ?? (_) {},
            onAdd: onAdd ?? (_) {},
            onClose: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  RelatedEntry entry() => const RelatedEntry(
        id: '42',
        title: 'Berserk',
        originalTitle: 'ベルセルク',
        type: 'manga',
        format: 'MANGA',
        year: 1997,
        relationType: 'ADAPTATION',
        score: 8.2,
        description: 'Dark fantasy story.',
        author: 'Kentaro Miura',
        episodes: 25,
      );

  testWidgets('null-item → ничего не рендерится', (tester) async {
    await pumpModal(tester, item: null);
    expect(find.byType(RelatedPreviewModal), findsOneWidget); // widget есть
    expect(find.textContaining('Berserk'), findsNothing); // контента нет
  });

  testWidgets('факт-строки: год/автор (manga-like)/счётчик гл.',
      (tester) async {
    await pumpModal(tester, item: entry());

    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('ベルセルク'), findsOneWidget);
    expect(find.textContaining('Год:'), findsOneWidget);
    expect(find.textContaining('Автор:'), findsOneWidget);
    expect(find.textContaining('Количество:'), findsOneWidget);
    expect(find.text('ADAPTATION'), findsOneWidget); // raw relationType
  });

  testWidgets('рейтинги: score-чип, отсутствие → «Рейтинг: Нет данных»',
      (tester) async {
    await pumpModal(
      tester,
      item: entry(),
      badges: [
        const RatingBadge(source: 'AniList', score: 8.2),
        const RatingBadge(source: 'MAL', score: null),
      ],
    );

    expect(find.text('AniList:'), findsOneWidget);
    expect(find.text('8.2'), findsOneWidget);
    expect(find.text('MAL:'), findsOneWidget);
  });

  testWidgets('описание: текст/italic-плейсхолдер', (tester) async {
    await pumpModal(tester, item: entry());
    expect(find.textContaining('Dark fantasy'), findsOneWidget);

    await pumpModal(
      tester,
      item: const RelatedEntry(id: '1', title: 'No Desc', type: 'manga'),
    );
    expect(find.textContaining('Описание отсутствует'), findsOneWidget);
  });

  testWidgets('добавление: тап «Добавить в библиотеку» → onAdd(status)',
      (tester) async {
    MediaStatus? added;
    await pumpModal(
      tester,
      item: entry(),
      status: MediaStatus.planned,
      onAdd: (s) => added = s,
      onStatusChange: (_) {},
    );

    await tester.tap(find.textContaining('Добавить в библиотеку'));
    await tester.pump();
    expect(added, MediaStatus.planned);
  });
}
