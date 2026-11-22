import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/backlog_health.dart';

AdvancedStats _makeStats({
  int totalTitles = 100,
  int completedTitles = 40,
  double completionRatePercent = 40.0,
  int? plannedTitles,
}) {
  final json = <String, dynamic>{
    'totalTitles': totalTitles,
    'completedTitles': completedTitles,
    'completionRatePercent': completionRatePercent,
    'totalHours': 500.0,
    'totalDays': 20.0,
    'gameHours': 100.0,
    'movieHours': 50.0,
    'seriesHours': 150.0,
    'animeHours': 100.0,
    'bookHours': 50.0,
    'mangaHours': 50.0,
    'totalPagesRead': 1000,
    'totalChaptersRead': 200,
    'totalEpisodesWatched': 300,
    'averageScore': 8.2,
    'scoreDistribution': <String, dynamic>{'8': 10.0},
    'averageScoreByType': <String, dynamic>{'game': 8.0},
    'currentStreakDays': 5,
  };
  if (plannedTitles != null) {
    json['plannedTitles'] = plannedTitles;
  }
  return AdvancedStats.fromJson(json);
}

Future<void> pumpBacklogHealth(
  WidgetTester tester, {
  required AdvancedStats stats,
  VoidCallback? onOpenStaleBacklog,
  double width = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: BacklogHealth(
                stats: stats,
                onOpenStaleBacklog: onOpenStaleBacklog,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('шапка: иконка Scale, тайтл бэклога', (tester) async {
    final stats = _makeStats();
    await pumpBacklogHealth(tester, stats: stats);

    expect(find.byIcon(LucideIcons.scale), findsOneWidget);
    expect(find.text('Баланс медиатеки (Индекс Цундоку)'), findsOneWidget);
  });

  testWidgets('легенда и бар: completed, inProgress, planned (без rawPlanned)',
      (tester) async {
    // total: 100, completed: 40 -> planned: 60, inProgress: 0
    final stats = _makeStats(totalTitles: 100, completedTitles: 40);
    await pumpBacklogHealth(tester, stats: stats);

    // Легенда
    expect(find.text('40'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    // Тултипы прогресс-бара
    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .toList();
    expect(tooltips.any((m) => m.contains('Завершено: 40 (40%)')), isTrue);
    expect(tooltips.any((m) => m.contains('В планах: 60 (60%)')), isTrue);
  });

  testWidgets('расчёт с rawPlanned: inProgress вычисляется как остаток',
      (tester) async {
    // total: 100, completed: 30, planned: 50 -> inProgress = 100 - 30 - 50 = 20
    final stats = _makeStats(
      totalTitles: 100,
      completedTitles: 30,
      plannedTitles: 50,
    );
    await pumpBacklogHealth(tester, stats: stats);

    expect(find.text('30'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);

    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .toList();
    expect(tooltips.any((m) => m.contains('В процессе: 20 (20%)')), isTrue);
  });

  testWidgets('вердикты: пустой, продуктивный, сбалансированный, цундоку',
      (tester) async {
    // Пустой
    await pumpBacklogHealth(
      tester,
      stats: _makeStats(totalTitles: 0, completedTitles: 0, completionRatePercent: 0),
    );
    expect(find.textContaining('Ваша медиатека пока пуста'), findsOneWidget);

    // Продуктивный >= 60%
    await pumpBacklogHealth(
      tester,
      stats: _makeStats(totalTitles: 10, completedTitles: 7, completionRatePercent: 70),
    );
    expect(find.textContaining('Высокая продуктивность'), findsOneWidget);

    // Сбалансированный >= 30% и < 60%
    await pumpBacklogHealth(
      tester,
      stats: _makeStats(totalTitles: 10, completedTitles: 4, completionRatePercent: 40),
    );
    expect(find.textContaining('Здоровый культурный баланс'), findsOneWidget);

    // Цундоку < 30%
    await pumpBacklogHealth(
      tester,
      stats: _makeStats(totalTitles: 10, completedTitles: 1, completionRatePercent: 10),
    );
    expect(find.textContaining('Истинный дух Цундоку'), findsOneWidget);
  });

  testWidgets('тап по ссылке ревизии вызывает onOpenStaleBacklog',
      (tester) async {
    var opened = false;
    final stats = _makeStats();
    await pumpBacklogHealth(
      tester,
      stats: stats,
      onOpenStaleBacklog: () => opened = true,
    );

    final link = find.text('Провести ревизию заброшенных тайтлов →');
    expect(link, findsOneWidget);

    await tester.tap(link);
    await tester.pump();
    expect(opened, isTrue);
  });
}
