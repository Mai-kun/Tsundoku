import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/time_distribution_donut.dart';

AdvancedStats _makeStats({
  double totalHours = 300.0,
  double gameHours = 120.0,
  double seriesHours = 60.0,
  double movieHours = 30.0,
  double animeHours = 45.0,
  double bookHours = 30.0,
  double mangaHours = 15.0,
  int totalEpisodesWatched = 50,
  int seriesEpisodesWatched = 30,
  int animeEpisodesWatched = 20,
  int totalPagesRead = 850,
  int totalChaptersRead = 120,
}) {
  return AdvancedStats.fromJson(<String, dynamic>{
    'totalTitles': 40,
    'completedTitles': 30,
    'completionRatePercent': 75.0,
    'totalHours': totalHours,
    'totalDays': 12.5,
    'gameHours': gameHours,
    'movieHours': movieHours,
    'seriesHours': seriesHours,
    'animeHours': animeHours,
    'bookHours': bookHours,
    'mangaHours': mangaHours,
    'totalPagesRead': totalPagesRead,
    'totalChaptersRead': totalChaptersRead,
    'totalEpisodesWatched': totalEpisodesWatched,
    'seriesEpisodesWatched': seriesEpisodesWatched,
    'animeEpisodesWatched': animeEpisodesWatched,
    'averageScore': 8.0,
    'scoreDistribution': <String, dynamic>{'8': 10.0},
    'averageScoreByType': <String, dynamic>{'game': 8.0},
    'currentStreakDays': 4,
  });
}

Future<void> pumpTimeDistributionDonut(
  WidgetTester tester, {
  required AdvancedStats stats,
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
              child: TimeDistributionDonut(stats: stats),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('центр кольца: общее время и подпись', (tester) async {
    final stats = _makeStats(totalHours: 350.0);
    await pumpTimeDistributionDonut(tester, stats: stats);

    expect(find.text('350 ч.'), findsOneWidget);
    expect(find.text('Всего времени'), findsOneWidget);
  });

  testWidgets('карточки 6 категорий: часы, проценты и доп. счётчики',
      (tester) async {
    // Total hours = 120+60+30+45+30+15 = 300.
    // game: 120/300 = 40%
    // series: 60/300 = 20%
    // movie: 30/300 = 10%
    // anime: 45/300 = 15%
    // book: 30/300 = 10%
    // manga: 15/300 = 5%
    final stats = _makeStats();
    await pumpTimeDistributionDonut(tester, stats: stats);

    // Лейблы
    expect(find.text('Игры'), findsOneWidget);
    expect(find.text('Сериалы'), findsOneWidget);
    expect(find.text('Фильмы'), findsOneWidget);
    expect(find.text('Аниме'), findsOneWidget);
    expect(find.text('Книги'), findsOneWidget);
    expect(find.text('Манга'), findsOneWidget);

    // Доп. текст
    expect(find.text('30 эп.'), findsOneWidget);
    expect(find.text('20 эп.'), findsOneWidget);
    expect(find.text('850 стр.'), findsOneWidget);
    expect(find.text('120 гл.'), findsOneWidget);

    // Проценты
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('15%'), findsOneWidget);
    expect(find.text('10%'), findsNWidgets(2)); // movie & book
    expect(find.text('5%'), findsOneWidget);
  });

  testWidgets('нулевое время: кольцо рендерится пустым, 0% на карточках',
      (tester) async {
    final stats = _makeStats(
      totalHours: 0.0,
      gameHours: 0.0,
      seriesHours: 0.0,
      movieHours: 0.0,
      animeHours: 0.0,
      bookHours: 0.0,
      mangaHours: 0.0,
    );
    await pumpTimeDistributionDonut(tester, stats: stats);

    expect(find.text('0 ч.'), findsWidgets);
    expect(find.text('0%'), findsNWidgets(6));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('адаптивный layout: desktop (>=600) -> Row, mobile (<600) -> Column',
      (tester) async {
    // Desktop: Row
    await pumpTimeDistributionDonut(tester, stats: _makeStats(), width: 800);
    expect(find.byType(Row), findsWidgets);

    // Mobile: ширина 400
    await pumpTimeDistributionDonut(tester, stats: _makeStats(), width: 400);
    expect(find.byType(Column), findsWidgets);
  });
}
