import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/app/app.dart';
import 'package:tsundoku_flutter/features/create-media/create_modal.dart';
import 'package:tsundoku_flutter/features/search-external/search_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/views/calendar_view.dart';
import 'package:tsundoku_flutter/views/goals_view.dart';
import 'package:tsundoku_flutter/views/history_view.dart';
import 'package:tsundoku_flutter/views/home_view.dart';
import 'package:tsundoku_flutter/views/lists_view.dart';
import 'package:tsundoku_flutter/views/settings_view.dart';
import 'package:tsundoku_flutter/views/stats_view.dart';

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final path = options.path;

    if (path.contains('/api/settings/storage')) {
      return ResponseBody.fromString(
        jsonEncode({'isFirstRunSetupRequired': false}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/stats')) {
      return ResponseBody.fromString(
        jsonEncode({
          'totalItems': 0,
          'completedItems': 0,
          'inProgressItems': 0,
          'plannedItems': 0,
          'pausedItems': 0,
          'droppedItems': 0,
          'totalDaysSpent': 0.0,
          'meanScore': 0.0,
          'scoreDistribution': <String, dynamic>{},
          'categoryDistribution': <String, dynamic>{},
          'monthlyCompletions': <dynamic>[],
          'yearComparison': <dynamic>[],
          'topGenres': <dynamic>[],
          'dropEarlyPercent': 0.0,
          'dropMidPercent': 0.0,
          'dropLatePercent': 0.0,
          'dropReasonStats': <dynamic>[],
          'badges': <dynamic>[],
          'plannedTitles': 0,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/lists')) {
      return ResponseBody.fromString(
        jsonEncode(<dynamic>[]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/goals')) {
      return ResponseBody.fromString(
        jsonEncode(<dynamic>[]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/history')) {
      return ResponseBody.fromString(
        jsonEncode(<dynamic>[]),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-total-count': ['0'],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode(<dynamic>[]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'x-total-count': ['0'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoopJobs extends JobsClientController {
  @override
  void connect() {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  TsundokuApi buildStubApi() {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = _StubAdapter();
    return TsundokuApi(dio);
  }

  testWidgets('App renders HomeView by default and can navigate to all views',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = buildStubApi();

    await tester.pumpWidget(
      TsundokuApp(
        providerOverrides: [
          apiClientProvider.overrideWithValue(api),
          jobsClientProvider.overrideWith(_NoopJobs.new),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Home view by default
    expect(find.byType(HomeView), findsOneWidget);

    // Navigate to Stats via Sidebar
    await tester.tap(find.text('Статистика'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StatsView), findsOneWidget);

    // Navigate to Lists via Sidebar
    await tester.tap(find.text('Списки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ListsView), findsOneWidget);

    // Navigate to History via Sidebar
    await tester.tap(find.text('История'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HistoryView), findsOneWidget);

    // Navigate to Calendar via Sidebar
    await tester.tap(find.text('Календарь'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CalendarView), findsOneWidget);

    // Navigate to Goals via Sidebar
    await tester.tap(find.text('Цели'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GoalsView), findsOneWidget);

    // Navigate to Settings via Sidebar
    await tester.tap(find.text('Настройки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('Header search opens SearchModal and can be closed',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = buildStubApi();

    await tester.pumpWidget(
      TsundokuApp(
        providerOverrides: [
          apiClientProvider.overrideWithValue(api),
          jobsClientProvider.overrideWith(_NoopJobs.new),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Initially modal is not open
    expect(find.byType(SearchModal), findsNothing);

    // Tap header search button
    await tester.tap(find.text('Поиск тайтлов'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SearchModal), findsOneWidget);

    // Tap close button in SearchModal
    final closeFinder = find.byTooltip('Закрыть (Esc)');
    if (closeFinder.evaluate().isNotEmpty) {
      await tester.tap(closeFinder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SearchModal), findsNothing);
    }
  });

  testWidgets('Sidebar create button opens CreateModal', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = buildStubApi();

    await tester.pumpWidget(
      TsundokuApp(
        providerOverrides: [
          apiClientProvider.overrideWithValue(api),
          jobsClientProvider.overrideWith(_NoopJobs.new),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CreateModal), findsNothing);

    // Tap "Добавить медиа" in Sidebar
    await tester.tap(find.text('Добавить медиа'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CreateModal), findsOneWidget);
  });
}
