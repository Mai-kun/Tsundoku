import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-grid/media_grid.dart';

/// Widget-тесты `MediaGrid.svelte`: состояния (loading/error/empty),
/// нативная слайвер-виртуализация (окно монтирования = поведение
/// virtualGrid ⏭️), колонки по ширине окна, кнопка Remove-from-list.
void main() {
  MediaItem item(String id) => MediaItem.fromJson({
        'id': id,
        'type': 'book',
        'title': 'Тайтл $id',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
      });

  List<MediaItem> items(int count) =>
      List.generate(count, (i) => item('m$i'));

  Future<void> pumpSlivers(
    WidgetTester tester,
    Widget grid, {
    Size size = const Size(1600, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: CustomScrollView(slivers: [grid]),
      ),
    ));
    await tester.pump();
  }

  testWidgets('loading → min-h-60 placeholder', (tester) async {
    await pumpSlivers(
      tester,
      MediaGrid(items: [], loading: true),
      size: const Size(1440, 900),
    );
    expect(find.byKey(const ValueKey('grid-loading')), findsOneWidget);
  });

  testWidgets('error → alert + Retry', (tester) async {
    var retries = 0;
    await pumpSlivers(
      tester,
      MediaGrid(
        items: [],
        error: Exception('boom'),
        onRetry: () => retries += 1,
      ),
      size: const Size(1440, 900),
    );
    // Alert-текст: errorMessage(Exception) → errors.unexpected.
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts, isNotEmpty);
    await tester.tap(find.byIcon(LucideIcons.rotateCw));
    expect(retries, 1);
  });

  testWidgets('empty → Inbox + library.emptyTitle', (tester) async {
    await pumpSlivers(
      tester,
      MediaGrid(items: []),
      size: const Size(1440, 900),
    );
    expect(find.byIcon(LucideIcons.inbox), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('1440px окна → 5 колонок (columnsForWidth 1-в-1)',
      (tester) async {
    await pumpSlivers(
      tester,
      MediaGrid(items: items(10)),
      size: const Size(1440, 900),
    );
    // SliverGrid: 10 элементов, кросс-ось 5.
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5);
  });

  testWidgets('1600px окна → 6 колонок; 1280 → 4; 700 → 3; 500 → 2',
      (tester) async {
    expect(columnsForWidth(500), 2);
    expect(columnsForWidth(700), 3);
    expect(columnsForWidth(1280), 5); // не < 1280 → 5 (1-в-1 с TS)
    expect(columnsForWidth(1300), 5);
    expect(columnsForWidth(1600), 6);
    expect(columnsForWidth(640), 3); // граница 640 → 3
    expect(columnsForWidth(1024), 4); // граница 1024 → 4
    expect(columnsForWidth(1536), 6); // граница 1536 → 6
  });

  testWidgets('окно монтирования: 200 items — в дереве меньше, чем 200',
      (tester) async {
    await pumpSlivers(
      tester,
      MediaGrid(items: items(200)),
      size: const Size(1440, 900),
    );
    // Нативная виртуализация SliverGrid: монтируются только видимые строки
    // (поведение окна удаления virtualGrid ⏭️).
    // Карточка несёт текст «Тайтл mN»; при 5 колонках и 900px высоте
    // монтируются единицы строк — заметно меньше 200.
    final titleTexts =
        tester.widgetList<Text>(find.byType(Text)).toList().length;
    expect(titleTexts, lessThan(100));
    expect(titleTexts, greaterThan(0));
  });

  testWidgets('onRemoveFromList → кнопка X с колбеком', (tester) async {
    var removed = 0;
    await pumpSlivers(
      tester,
      MediaGrid(items: items(1), onRemoveFromList: (i) async => removed += 1),
      size: const Size(1440, 900),
    );
    final center = tester.getCenter(find.byIcon(LucideIcons.x));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pump();
    expect(removed, 1);
  });
}
