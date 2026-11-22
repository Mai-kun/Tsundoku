import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/widgets/stats/monthly_activity_chart.dart';

Future<void> pumpChart(WidgetTester tester, {double width = 800}) async {
  const completions = [
    MonthlyCompletionItem(monthYear: '2026-01', count: 12),
    MonthlyCompletionItem(monthYear: '2026-02', count: 0),
    MonthlyCompletionItem(monthYear: '2026-03', count: 6),
    MonthlyCompletionItem(monthYear: '2026-04', count: 3),
  ];
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Material(
        child: Center(
          child: SizedBox(
            width: width,
            child: MonthlyActivityChart(completions: completions),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('шапка: иконка, тайтл, бейдж-итог', (tester) async {
    await pumpChart(tester);
    expect(find.text('Активность за 12 месяцев'), findsOneWidget);
    expect(find.byIcon(LucideIcons.calendarDays), findsOneWidget);
    expect(find.text('21 за год'), findsOneWidget); // 12+6+3
  });

  testWidgets('колонки: count-числа, нулевой месяц — плашка', (tester) async {
    await pumpChart(tester);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // Нулевой месяц: числа нет.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('подписи месяцев (ru-локаль, short)', (tester) async {
    await pumpChart(tester);
    expect(find.text('янв.'), findsOneWidget);
    expect(find.text('февр.'), findsOneWidget);
    expect(find.text('март'), findsOneWidget);
    expect(find.text('апр.'), findsOneWidget);
  });

  testWidgets('тултипы месяцев с завершениями', (tester) async {
    await pumpChart(tester);
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tp) => tp.message ?? '')
        .toList();
    expect(messages.any((m) => m.contains('янв. 2026') &&
        m.contains(': 12 завершено')), isTrue);
    expect(messages.any((m) => m.contains('мар. 2026') &&
        m.contains(': 6 завершено')), isTrue);
    expect(messages.length, 3); // только ненулевые
  });

  testWidgets('узкий вьюпорт: горизонтальный скролл (min 340)', (tester) async {
    await pumpChart(tester, width: 200);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .scrollDirection,
        Axis.horizontal);
  });

  testWidgets('высоты колонок пропорциональны count (FractionallySizedBox)',
      (tester) async {
    await pumpChart(tester);
    final boxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    // 12 → 1.0, 6 → 0.5, 3 → 0.25.
    final factors = boxes.map((b) => b.heightFactor).toList();
    expect(factors.contains(1.0), isTrue);
    expect(factors.contains(0.5), isTrue);
    expect(factors.contains(0.25), isTrue);
  });
}
