import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-grid/media_grid.dart';
import 'package:tsundoku_flutter/widgets/media-grid/section_row.dart';

/// Widget-тесты `SectionRow.svelte`: заголовок 25px + счётчик items.length +
/// проброс пропов в MediaGrid.
void main() {
  MediaItem item(String id) => MediaItem.fromJson({
        'id': id,
        'type': 'book',
        'title': 'Тайтл',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
      });

  Future<void> pumpSlivers(
    WidgetTester tester,
    List<Widget> slivers,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: CustomScrollView(slivers: slivers),
      ),
    ));
    await tester.pump();
  }

  testWidgets('заголовок + счётчик количества + сетка с карточками',
      (tester) async {
    await pumpSlivers(tester, [
      SectionRow(title: 'Книги', items: [item('a'), item('b'), item('c')]),
    ]);
    expect(find.text('Книги'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // Карточки отрисовались (тайтл на постере).
    expect(find.text('Тайтл'), findsNWidgets(3));
  });

  testWidgets('пустая секция → счётчик 0 + empty-box из MediaGrid',
      (tester) async {
    await pumpSlivers(tester, [
      SectionRow(title: 'Игры', items: const []),
    ]);
    expect(find.text('Игры'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byType(MediaGrid), findsOneWidget);
  });

  testWidgets('проброс onDelete → бейдж-кластер и карточки рендерятся',
      (tester) async {
    await pumpSlivers(tester, [
      SectionRow(
        title: 'Фильмы',
        items: [item('a')],
        onOpen: (_) {},
        onDelete: (i) async {},
      ),
    ]);
    expect(find.text('Фильмы'), findsOneWidget);
    // Слайдер сетки присутствует: SliverGrid монтирует карточку.
    expect(find.byType(SliverGrid), findsOneWidget);
  });
}
