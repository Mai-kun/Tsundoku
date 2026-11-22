import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/tracker_badges.dart';

AdvancedStats _makeStats({
  int completedTitles = 100, // hundred_club unlocked
  int totalPagesRead = 600,
  int totalChaptersRead = 500, // bibliophile: 1100 >= 1000 unlocked
  int currentStreakDays = 5, // streak_master: 5 < 7 locked
  double totalHours = 80.0, // time_keeper: 80 < 100 locked
  Map<String, dynamic> scoreDistribution = const {'10': 1.0}, // perfectionist: 1 < 3 locked
  double gameHours = 10.0,
  double movieHours = 5.0,
  double seriesHours = 0.0,
  double animeHours = 0.0,
  double bookHours = 0.0,
  double mangaHours = 0.0, // omnivore: 2 active formats < 4 locked
}) {
  return AdvancedStats.fromJson(<String, dynamic>{
    'totalTitles': 120,
    'completedTitles': completedTitles,
    'completionRatePercent': 83.3,
    'totalHours': totalHours,
    'totalDays': 3.3,
    'gameHours': gameHours,
    'movieHours': movieHours,
    'seriesHours': seriesHours,
    'animeHours': animeHours,
    'bookHours': bookHours,
    'mangaHours': mangaHours,
    'totalPagesRead': totalPagesRead,
    'totalChaptersRead': totalChaptersRead,
    'totalEpisodesWatched': 50,
    'averageScore': 8.5,
    'scoreDistribution': scoreDistribution,
    'averageScoreByType': <String, dynamic>{'game': 8.0},
    'currentStreakDays': currentStreakDays,
  });
}

Future<void> pumpTrackerBadges(
  WidgetTester tester, {
  required AdvancedStats stats,
  double width = 1000,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: TrackerBadges(stats: stats),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('шапка: трофей, заголовок, счётчик разблокированных',
      (tester) async {
    // 2 unlocked (hundred_club & bibliophile)
    final stats = _makeStats();
    await pumpTrackerBadges(tester, stats: stats);

    expect(find.byIcon(LucideIcons.trophy), findsOneWidget);
    expect(find.text('Достижения медиатеки'), findsOneWidget);
    expect(find.text('2 из 6 разблокировано (33%)'), findsOneWidget);
  });

  testWidgets('все 6 бейджей отображаются с тайтлами и описаниями',
      (tester) async {
    final stats = _makeStats();
    await pumpTrackerBadges(tester, stats: stats);

    expect(find.text('Клуб сотен'), findsOneWidget);
    expect(find.text('Завершить 100 произведений'), findsOneWidget);

    expect(find.text('Библиофил'), findsOneWidget);
    expect(find.text('Прочитать 1,000+ страниц или глав'), findsOneWidget);

    expect(find.text('Мастер стриков'), findsOneWidget);
    expect(find.text('Удержать стрик активности от 7 дней'), findsOneWidget);

    expect(find.text('Хранитель времени'), findsOneWidget);
    expect(find.text('Провести суммарно 100+ часов за медиа'), findsOneWidget);

    expect(find.text('Перфекционист'), findsOneWidget);
    expect(find.text('Поставить 10 звезд хотя бы 3 тайтлам'), findsOneWidget);

    expect(find.text('Культурный омнивор'), findsOneWidget);
    expect(find.text('Активность хотя бы в 4 форматах медиа'), findsOneWidget);
  });

  testWidgets('разблокированные и заблокированные состояния бейджей',
      (tester) async {
    final stats = _makeStats();
    await pumpTrackerBadges(tester, stats: stats);

    // 2 разблокированных бейджа -> 2 плашки 'РАЗБЛОКИРОВАНО ✓'
    expect(find.text('РАЗБЛОКИРОВАНО ✓'), findsNWidgets(2));

    // 4 заблокированных -> 4 плашки 'Прогресс'
    expect(find.text('Прогресс'), findsNWidgets(4));

    // Мастер стриков: 5 / 7 (71%)
    expect(find.text('5 / 7 (71%)'), findsOneWidget);

    // Хранитель времени: 80 / 100 (80%)
    expect(find.text('80 / 100 (80%)'), findsOneWidget);

    // Перфекционист: 1 / 3 (33%)
    expect(find.text('1 / 3 (33%)'), findsOneWidget);

    // Культурный омнивор: 2 / 4 (50%)
    expect(find.text('2 / 4 (50%)'), findsOneWidget);
  });

  testWidgets('все бейджи разблокированы (6 из 6)', (tester) async {
    final stats = _makeStats(
      completedTitles: 150,
      totalPagesRead: 1000,
      totalChaptersRead: 500,
      currentStreakDays: 14,
      totalHours: 200.0,
      scoreDistribution: {'10': 5.0},
      gameHours: 50.0,
      movieHours: 20.0,
      seriesHours: 40.0,
      animeHours: 30.0,
      bookHours: 20.0,
      mangaHours: 10.0,
    );
    await pumpTrackerBadges(tester, stats: stats);

    expect(find.text('6 из 6 разблокировано (100%)'), findsOneWidget);
    expect(find.text('РАЗБЛОКИРОВАНО ✓'), findsNWidgets(6));
    expect(find.text('Прогресс'), findsNothing);
  });
}
