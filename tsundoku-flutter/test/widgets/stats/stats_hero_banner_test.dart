import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/stats_hero_banner.dart';

AdvancedStats _stats() => AdvancedStats.fromJson(<String, dynamic>{
      'totalTitles': 1234,
      'completedTitles': 500,
      'completionRatePercent': 40.5,
      'totalHours': 2500.4,
      'totalDays': 104.2,
      'averageScore': 7.8,
      'currentStreakDays': 12,
      'totalPagesRead': 0,
      'totalChaptersRead': 0,
      'totalEpisodesWatched': 0,
      'gameHours': 0.0,
      'movieHours': 0.0,
      'seriesHours': 0.0,
      'animeHours': 0.0,
      'bookHours': 0.0,
      'mangaHours': 0.0,
      'scoreDistribution': <String, dynamic>{},
      'averageScoreByType': <String, dynamic>{},
    });

void main() {
  Future<void> pumpBanner(WidgetTester tester, {double width = 1000}) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: StatsHeroBanner(stats: _stats()),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('hero: тайтл с числами (ru-локаль, пробелы), подзаголовок',
      (tester) async {
    await pumpBanner(tester);
    expect(find.textContaining('Вы провели 2,500 ч. за 1,234 тайтлами.'),
        findsNothing); // ru-локаль: пробелы
    expect(find.textContaining('Вы провели 2 500 ч. за 1 234 тайтлами.'),
        findsOneWidget);
    expect(find.textContaining('104 дн.'), findsOneWidget);
  });

  testWidgets('три метрики: стрик, средний балл, завершения', (tester) async {
    await pumpBanner(tester);
    expect(find.textContaining('Стрик активности'), findsOneWidget);
    expect(find.textContaining('12 дн. активности подряд'), findsOneWidget);
    expect(find.textContaining('Средний балл'), findsOneWidget);
    expect(find.textContaining('7.8 / 10'), findsOneWidget);
    expect(find.textContaining('Завершено'), findsOneWidget);
    expect(find.textContaining('500 / 1234 (40.5%)'), findsOneWidget);
    expect(find.byIcon(LucideIcons.flame), findsOneWidget);
    expect(find.byIcon(LucideIcons.star), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle), findsOneWidget);
  });

  testWidgets('узкий вьюпорт: метрики в 1 колонку', (tester) async {
    await pumpBanner(tester, width: 400);
    // Wrap-элементы в 1 колонку — три ряда.
    final cards = find.byIcon(LucideIcons.flame);
    expect(cards, findsOneWidget);
    final starCenter = tester.getCenter(find.byIcon(LucideIcons.star));
    final flameCenter = tester.getCenter(find.byIcon(LucideIcons.flame));
    expect(starCenter.dy, greaterThan(flameCenter.dy)); // колонкой
  });

  testWidgets('averageScore=0 → тире', (tester) async {
    final stats = AdvancedStats.fromJson(<String, dynamic>{
      'totalTitles': 5,
      'completedTitles': 1,
      'completionRatePercent': 20.0,
      'totalHours': 10.0,
      'totalDays': 1.0,
      'averageScore': 0.0,
      'currentStreakDays': 0,
      'totalPagesRead': 0,
      'totalChaptersRead': 0,
      'totalEpisodesWatched': 0,
      'gameHours': 0.0,
      'movieHours': 0.0,
      'seriesHours': 0.0,
      'animeHours': 0.0,
      'bookHours': 0.0,
      'mangaHours': 0.0,
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 1000,
              child: StatsHeroBanner(stats: stats),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('— / 10'), findsOneWidget);
  });
}
