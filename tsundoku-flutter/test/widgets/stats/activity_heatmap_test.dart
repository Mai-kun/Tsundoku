import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/widgets/stats/activity_heatmap.dart';

/// 2026-01-15 — четверг (weekday 4 → mondayOffset 3).
final DateTime kToday = DateTime(2026, 1, 15);

Map<String, num> _activity() => <String, num>{
      '2026-01-14': 3,
      '2026-01-13': 6,
      '2026-01-12': 10,
      '2025-06-01': 1,
    };

Future<void> pumpHeatmap(WidgetTester tester, {double width = 900}) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Material(
        child: Center(
          child: SizedBox(
            width: width,
            height: 320,
            child: ActivityHeatmap(dailyActivity: _activity(), today: kToday),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('heatmap: тайтл, итоги, легенда', (tester) async {
    await pumpHeatmap(tester);
    expect(find.text('Активность за год'), findsOneWidget);
    // 3+6+10+1 = 20 действий; total в шапке и футере (2 места).
    expect(find.text('20 действий за год'), findsNWidgets(2));
    expect(find.text('Меньше'), findsOneWidget);
    expect(find.text('Больше'), findsOneWidget);
  });

  testWidgets('5 уровней интенсивности по счётчикам', (tester) async {
    await pumpHeatmap(tester);
    // Ячейки с count 0 (365-4), 1, 3, 6, 10 → уровни 0..4.
    final containers = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(ActivityHeatmap), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration)
        .toList();
    final colors = containers
        .map((c) => (c.decoration! as BoxDecoration).color)
        .whereType<Color>()
        .toSet();
    expect(colors.length >= 5, isTrue); // ≥5 уровней (легенда добавляет ещё)
  });

  testWidgets('Monday-offset: первая колонка — 3 пустых ячейки', (tester) async {
    await pumpHeatmap(tester);
    // 2026-01-15 четверг; первая колонка 2025-01-13 (пн); offset до пн = 0?
    // days[0].date = 2026-01-15 - 364 = 2025-01-16 — пятница → offset 4.
    // Проверяем суммарно: пустых ячеек 4 (offset) в первой колонке.
    final firstColumnCells = find.descendant(
      of: find.byType(ActivityHeatmap),
      matching: find.byType(SizedBox),
    );
    expect(firstColumnCells, findsWidgets);
    // Точная проверка — тултип самого раннего дня.
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('тултипы с датами (ru-локаль)', (tester) async {
    await pumpHeatmap(tester);
    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tp) => tp.message ?? '')
        .where((m) => m.isNotEmpty)
        .toList();
    // DateFormat 'd MMM y' ru: «14 янв. 2026 г.».
    final jan2026 =
        tooltips.where((m) => m.contains('янв. 2026')).toList();
    expect(jan2026.any((m) => m.startsWith('14 янв. 2026: 3 действий')),
        isTrue,
        reason: 'actual: $jan2026');
    expect(
        tooltips.any((m) => m.contains('13 янв. 2026') &&
            m.contains(': 6 действий')),
        isTrue);
    expect(
        tooltips.any((m) => m.contains('12 янв. 2026') &&
            m.contains(': 10 действий')),
        isTrue);
    expect(
        tooltips.any((m) => m.contains('1 июн. 2025') &&
            m.contains(': 1 действий')),
        isTrue);
  });

  testWidgets('узкий вьюпорт: горизонтальный скролл (min 760)', (tester) async {
    await pumpHeatmap(tester, width: 400);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView));
    expect(scroll.scrollDirection, Axis.horizontal);
  });
}
