import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/rating_psychology.dart';

AdvancedStats _makeStats({
  double averageScore = 8.2,
  Map<String, dynamic> scoreDistribution = const {
    '10': 5.0,
    '9': 15.0,
    '8': 20.0,
    '7': 10.0,
    '6': 0.0,
  },
  Map<String, dynamic> averageScoreByType = const {
    'game': 8.5,
    'movie': 7.0,
    'book': 0.0, // filtered out
  },
}) {
  return AdvancedStats.fromJson(<String, dynamic>{
    'totalTitles': 50,
    'completedTitles': 40,
    'completionRatePercent': 80.0,
    'totalHours': 300.0,
    'totalDays': 12.0,
    'gameHours': 100.0,
    'movieHours': 50.0,
    'seriesHours': 50.0,
    'animeHours': 50.0,
    'bookHours': 25.0,
    'mangaHours': 25.0,
    'totalPagesRead': 500,
    'totalChaptersRead': 100,
    'totalEpisodesWatched': 150,
    'averageScore': averageScore,
    'scoreDistribution': scoreDistribution,
    'averageScoreByType': averageScoreByType,
    'currentStreakDays': 3,
  });
}

Future<void> pumpRatingPsychology(
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
              child: RatingPsychology(stats: stats),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('шапка: тайтл и бейдж средней оценки', (tester) async {
    final stats = _makeStats(averageScore: 8.4);
    await pumpRatingPsychology(tester, stats: stats);

    expect(find.text('Психология оценок'), findsOneWidget);
    expect(find.text('Средняя: 8.4 ★'), findsOneWidget);
  });

  testWidgets('averageScore <= 0: бейдж средней оценки скрыт', (tester) async {
    final stats = _makeStats(averageScore: 0.0);
    await pumpRatingPsychology(tester, stats: stats);

    expect(find.text('Психология оценок'), findsOneWidget);
    expect(find.textContaining('Средняя:'), findsNothing);
  });

  testWidgets('распределение: 10 строк оценок и пропорциональные бары',
      (tester) async {
    // maxCount = 20 (оценка 8)
    final stats = _makeStats();
    await pumpRatingPsychology(tester, stats: stats);

    // Все 10 оценок присутствуют
    for (int score = 1; score <= 10; score++) {
      expect(find.text('$score ★'), findsOneWidget);
    }

    // Счётчики: 20 (оценка 8), 15 (оценка 9), 10 (оценка 7), 5 (оценка 10)
    expect(find.text('20'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    // Проверка относительных факторов FractionallySizedBox:
    // 20/20 = 1.0; 10/20 = 0.5
    final boxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    final factors = boxes.map((b) => b.widthFactor).toList();
    expect(factors.contains(1.0), isTrue);
    expect(factors.contains(0.5), isTrue);
  });

  testWidgets('средний балл по категориям: отображаются только ненулевые',
      (tester) async {
    final stats = _makeStats(
      averageScoreByType: {
        'game': 8.5,
        'movie': 7.2,
        'anime': 9.0,
        'book': 0.0, // не рендерится
      },
    );
    await pumpRatingPsychology(tester, stats: stats);

    expect(find.text('СРЕДНИЙ БАЛЛ ПО КАТЕГОРИЯМ'), findsOneWidget);
    expect(find.text('Игры: '), findsOneWidget);
    expect(find.text('8.5 ★'), findsOneWidget);
    expect(find.text('Фильмы: '), findsOneWidget);
    expect(find.text('7.2 ★'), findsOneWidget);
    expect(find.text('Аниме: '), findsOneWidget);
    expect(find.text('9.0 ★'), findsOneWidget);

    // 'Книги' не должны отображаться
    expect(find.text('Книги: '), findsNothing);
  });

  testWidgets('если все средние по категориям 0 — секция скрыта',
      (tester) async {
    final stats = _makeStats(
      averageScoreByType: {
        'game': 0.0,
        'movie': 0.0,
      },
    );
    await pumpRatingPsychology(tester, stats: stats);

    expect(find.text('СРЕДНИЙ БАЛЛ ПО КАТЕГОРИЯМ'), findsNothing);
  });
}
