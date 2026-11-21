import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/notes_section.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/quotes_section.dart';
import 'package:tsundoku_flutter/widgets/media-detail/tabs/overview_tab.dart';

/// Тесты `OverviewTab.svelte`: диспетчер прогресс-блока по типу, лестница
/// блоков (две колонки lg / один поток), creator-вывод.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media(String type, Map<String, Object?> extra) =>
      MediaDetail.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'X',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  Future<void> pumpTab(
    WidgetTester tester, {
    required MediaDetail media,
    ProgressInfo? support,
    int progressValue = 3,
    double progressPercent = 30,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Stub-API: секции (files/linked-sources) делают запросы на монтировании.
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = _StubAdapter();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: OverviewTab(
              media: media,
              support: support,
              progressValue: progressValue,
              progressPercent: progressPercent,
              progressError: null,
              onStep: (_) {},
              onCounterChange: (_) {},
              achievements: const [],
              achievementsTotal: 0,
              achievementsLoading: false,
              achievementsBusy: false,
              achievementsTruncated: false,
              unlockedAchievementNames: const {},
              onToggleAchievement: (_) async {},
              onToggleAllAchievements: () async {},
              onOpenMedia: (_) {},
              onSearch: (_) {},
              onEdit: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    // dio/секционные таймеры (0ms) — флаш перед teardown.
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('книга: БЫСТРЫЕ ФАКТЫ + прогресс-страницы + Об издании + заметки',
      (tester) async {
    await pumpTab(
      tester,
      media: media('book', {'totalPages': 320, 'author': 'Миядзаки'}),
      support: const ProgressInfo(
          current: 40, total: 320, editable: true, label: 'Страницы'),
      progressValue: 40,
      progressPercent: 12.5,
    );

    expect(find.textContaining('Быстрые факты'), findsOneWidget);
    expect(find.text('СТРАНИЦЫ'), findsOneWidget);
    expect(find.text('ОБ ИЗДАНИИ'), findsOneWidget);
    expect(find.text('Ваши заметки и мысли'), findsOneWidget);
    expect(find.text('АВТОР'), findsOneWidget);
    expect(find.text('Миядзаки'), findsOneWidget);
  });

  testWidgets('movie без support: плашка статуса вместо прогресса',
      (tester) async {
    await pumpTab(
      tester,
      media: media('movie', {'durationMinutes': 136}),
      support: null,
    );

    expect(find.text('ХРОНОМЕТРАЖ И СТАТУС'), findsOneWidget);
    expect(find.text('136 мин.'), findsNWidgets(2)); // status-секция + quick-facts
  });

  testWidgets('tvshow с support: СЕРИИ + «В вашей коллекции» нет без автора',
      (tester) async {
    await pumpTab(
      tester,
      media: media('tvshow', {
        'totalEpisodesCount': 13,
        'episodeDurationMinutes': 24,
        'isAnime': true,
      }),
      support: const ProgressInfo(
          current: 3, total: 13, editable: true, label: 'Серии'),
      progressValue: 3,
      progressPercent: 23.1,
    );

    expect(find.text('СЕРИИ'), findsOneWidget);
    // Creator: studio отсутствует → noCreator-заглушка.
    expect(find.textContaining('Информация о создателе'), findsOneWidget);
  });

  testWidgets('quotesJson пуст → секции цитат нет; game → GameDetail',
      (tester) async {
    await pumpTab(
      tester,
      media: media('game', {'studio': 'Team Cherry'}),
      support: null,
      progressValue: 42,
    );

    expect(find.textContaining('Достижения не загружены'), findsOneWidget);
    expect(find.text('РАЗРАБОТЧИК'), findsOneWidget);
    // Цитаты: game без quotesJson → нет.
    expect(find.textContaining('ЦИТАТЫ И ВЫПИСКИ'), findsNothing);
  });

  testWidgets('с цитатами: QuotesSection рендерится',
      (tester) async {
    await pumpTab(
      tester,
      media: media('book', {
        'totalPages': 100,
        'quotesJson': jsonEncodeQuoted(),
      }),
      support: const ProgressInfo(
          current: 1, total: 100, editable: true, label: 'Страницы'),
    );

    expect(find.byType(QuotesSection), findsOneWidget);
    expect(find.byType(NotesSection), findsOneWidget);
  });
}

String jsonEncodeQuoted() => '{"q": "x"}';

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode([]), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
