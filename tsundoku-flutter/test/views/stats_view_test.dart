import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/views/stats_view.dart';

AdvancedStats _makeStats() {
  return AdvancedStats.fromJson(<String, dynamic>{
    'totalTitles': 50,
    'completedTitles': 35,
    'completionRatePercent': 70.0,
    'totalHours': 120.0,
    'totalDays': 5.0,
    'averageScore': 8.4,
    'currentStreakDays': 7,
    'gameHours': 50.0,
    'movieHours': 20.0,
    'seriesHours': 30.0,
    'animeHours': 15.0,
    'bookHours': 5.0,
    'mangaHours': 0.0,
    'totalMoviesWatched': 10,
    'totalEpisodesWatched': 45,
    'totalPagesRead': 1500,
    'totalChaptersRead': 0,
    'gamesCompleted': 5,
    'moviesCompleted': 10,
    'seriesCompleted': 4,
    'animeCompleted': 3,
    'booksCompleted': 2,
    'mangaCompleted': 0,
    'scoreDistribution': {'8': 10, '9': 15},
    'averageScoreByType': {
      'game': 8.0,
      'movie': 8.5,
      'series': 8.2,
      'anime': 9.0,
      'book': 7.5,
      'manga': 0.0,
    },
    'monthlyCompletions': [
      {'monthYear': '2026-01', 'count': 5},
    ],
    'topGenres': [
      {'genre': 'action', 'count': 15, 'percentage': 30.0},
    ],
    'topGenresByType': <String, dynamic>{},
    'dailyActivity': {'2026-01-01': 3.0},
    'plannedTitles': 10,
    'unlockedBadgesCount': 3,
    'badges': <dynamic>[],
  });
}

TasteProfile _makeProfile() {
  return const TasteProfile(
    persona: TastePersona(
      icon: 'critic',
      title: 'Строгий критик',
      description: 'Высокие стандарты',
      traits: ['Честные оценки'],
    ),
    sunkCost: SunkCost(
      lowScoreHours: 10.0,
      percentageOfTotal: 5.0,
      titlesCount: 2,
      categoryBreakdown: {'game': 10.0},
    ),
    divergence: CriticalDivergence(
      hiddenGem: null,
      disappointment: null,
    ),
    genreParadox: [],
    eraAffinity: [],
    genreRadar: [],
    dropAnalytics: null,
  );
}

class _StubStatsApi extends TsundokuApi {
  final Future<AdvancedStats> Function(String scope)? onGetStats;
  final Future<TasteProfile> Function(String scope)? onGetProfile;

  _StubStatsApi({
    this.onGetStats,
    this.onGetProfile,
  }) : super(Dio());

  @override
  Future<AdvancedStats> getAdvancedStats({
    String scope = 'completed',
    CancelToken? cancelToken,
  }) {
    if (onGetStats != null) return onGetStats!(scope);
    return Future.value(_makeStats());
  }

  @override
  Future<TasteProfile> getTasteProfile({
    String scope = 'completed',
    CancelToken? cancelToken,
  }) {
    if (onGetProfile != null) return onGetProfile!(scope);
    return Future.value(_makeProfile());
  }
}

Future<void> pumpStatsView(
  WidgetTester tester, {
  required TsundokuApi api,
  int refreshKey = 0,
  ValueChanged<String>? onOpenMedia,
  double width = 1200,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: StatsView(
                refreshKey: refreshKey,
                onOpenMedia: onOpenMedia,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('loading state: скелетоны отображаются во время запроса',
      (tester) async {
    final completer = Completer<AdvancedStats>();
    final api = _StubStatsApi(
      onGetStats: (_) => completer.future,
    );

    await pumpStatsView(tester, api: api);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Вкладки видны всегда в шапке
    expect(find.text('Сводка'), findsOneWidget);
    expect(find.text('Профиль вкуса'), findsOneWidget);

    completer.complete(_makeStats());
    await tester.pumpAndSettle();
  });

  testWidgets('ошибка загрузки: отображается сообщение и кнопка retry',
      (tester) async {
    int calls = 0;
    final api = _StubStatsApi(
      onGetStats: (_) {
        calls++;
        if (calls == 1) {
          return Future.error(Exception('Ошибка сети'));
        }
        return Future.value(_makeStats());
      },
    );

    await pumpStatsView(tester, api: api);
    await tester.pumpAndSettle();

    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.text('Сводка'), findsOneWidget);
    expect(find.text('35 / 50 (70%)'), findsOneWidget);
  });

  testWidgets('успешная сводка: рендерится баннер, графики и виджеты',
      (tester) async {
    final api = _StubStatsApi();

    await pumpStatsView(tester, api: api);
    await tester.pumpAndSettle();

    // Табы
    expect(find.text('Сводка'), findsOneWidget);
    expect(find.text('Профиль вкуса'), findsOneWidget);

    // Селектор области учета
    expect(find.text('✓ Только завершённые'), findsOneWidget);
    expect(find.text('⚡ Все с прогрессом'), findsOneWidget);

    // Hero banner
    expect(find.text('35 / 50 (70%)'), findsOneWidget);
    expect(find.text('8.4 / 10'), findsOneWidget);
    expect(find.text('7 дн. активности подряд'), findsOneWidget);

    // Виджеты статистики
    expect(find.text('120 ч.'), findsOneWidget);
    expect(find.text('Психология оценок'), findsOneWidget);
    expect(find.textContaining('Индекс Цундоку'), findsOneWidget);
  });

  testWidgets('переключение на вкладку "Профиль вкуса"', (tester) async {
    final api = _StubStatsApi(
      onGetProfile: (_) => Future.value(_makeProfile()),
    );

    await pumpStatsView(tester, api: api);
    await tester.pumpAndSettle();

    // Кликаем по вкладке "Профиль вкуса"
    await tester.tap(find.text('Профиль вкуса'));
    await tester.pumpAndSettle();

    // TastePersonaCard
    expect(find.text('АРХЕТИП ВКУСА'), findsOneWidget);
    expect(find.text('Строгий критик'), findsOneWidget);

    // SunkCostCard
    expect(find.text('Синдром потерянного времени'), findsOneWidget);

    // CriticalDivergenceCard
    expect(find.text('Я против всего мира'), findsOneWidget);
  });
}
