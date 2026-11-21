import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/types/index.dart' show PendingMatchItemDto;
import 'package:tsundoku_flutter/widgets/layout/activity_dropdown.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// Widget-тесты `ActivityDropdown.svelte`: бейджи active/pending, поповер
/// (очередь с прогрессом и отменой, pending-review, лимиты API, open-window).
/// No-op jobs-контроллер: SSE-машина (connect с таймерами) покрыта своими
/// тестами; dropdown-тесты подменяют её, чтобы не ловить pending timers.
class _NoopJobs extends JobsClientController {
  @override
  void connect() {}
  // disconnect НЕ переопределяется: таймеры задач (eviction/safety) обязаны
  // отменяться при teardown (ref.onDispose → disconnect).
}

void main() {
  late ProviderContainer container;
  late StubAdapter adapter;

  Future<void> pumpDropdown(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 40, right: 40),
              child: ActivityDropdown(),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) => jsonBody(<String, Object?>{}));
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      jobsClientProvider.overrideWith(_NoopJobs.new),
    ]);
    container.read(jobsClientProvider.notifier).attachApi(api);
    addTearDown(container.dispose);
  });

  void seedJob(WidgetTester tester,
      {String status = 'Running', int percent = 45}) {
    // Публичный SSE-вход контроллера: применяем raw payload задачи.
    container.read(jobsClientProvider.notifier).applyJson(jsonEncode({
      'jobId': 'j1',
      'mediaId': null,
      'title': 'Обновление метаданных',
      'progressPercent': percent,
      'currentStep': 'Загрузка',
      'status': status,
      'startedAt': '2024-01-01T00:00:00Z',
      'errorMessage': null,
    }));
  }

  testWidgets('бейдж active при активной задаче, нет бейджа без задач',
      (tester) async {
    await pumpDropdown(tester);
    // Без задач — бейджа нет.
    expect(find.text('1'), findsNothing);

    seedJob(tester, status: 'Running', percent: 45);
    await pumpDropdown(tester);
    // Появился бейдж active «1».
    expect(find.text('1'), findsOneWidget);
    // Safety-таймер задачи (70s) — прокачать, чтобы teardown был чистым.
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('тап → поповер: очередь с прогрессом и статусом', (tester) async {
    seedJob(tester, status: 'Running', percent: 45);
    await pumpDropdown(tester);
    await tester.tap(find.byIcon(LucideIcons.activity));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ФОНОВЫЕ ПРОЦЕССЫ'), findsOneWidget);
    expect(find.text('Обновление метаданных'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
    // Кнопка отмены для Running.
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    // Отмена → DELETE /api/jobs/j1.
    await tester.tap(find.byIcon(LucideIcons.x).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      adapter.seen.any((o) => o.path.contains('/api/jobs/j1')),
      isTrue,
      reason: 'cancel(jobId) — запрос на отмену',
    );
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('пустая очередь → empty + emptyHint', (tester) async {
    await pumpDropdown(tester);
    await tester.tap(find.byIcon(LucideIcons.activity));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Нет активных задач'), findsOneWidget);
  });

  testWidgets('pendingMatches → amber-кнопка review', (tester) async {
    // Тест-хук: refreshPendingMatches в проде делает connect (см. строку
    // ActivityDropdown в FLUTTER_MIGRATION.md).
    container.read(jobsClientProvider.notifier).setPendingMatchesForTest([
      PendingMatchItemDto.fromJson({
        'id': 'p1',
        'title': 'Тайтл',
        'type': 'anime',
      }),
    ]);
    await pumpDropdown(tester);
    await tester.tap(find.byIcon(LucideIcons.activity));
    await tester.pump(const Duration(milliseconds: 300));
    // pendingCount ≥ 1 → кнопка с текстом pendingCount.
    expect(find.byIcon(LucideIcons.activity), findsOneWidget);
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.any((w) => w.data != null && w.data!.contains('1')), isTrue,
        reason: 'pendingCount кнопка содержит число');
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('rate limits: unlimited и полоса remaining', (tester) async {
    // Заготовленный ответ getRateLimits.
    adapter = StubAdapter((options) {
      if (options.path.contains('/api/system/rate-limits')) {
        return jsonBody([
          {'provider': 'Shikimori', 'remaining': 0, 'limit': 0, 'resetSecondsRemaining': 0, 'updatedAt': ''},
          {'provider': 'AniList', 'remaining': 25, 'limit': 90, 'resetSecondsRemaining': 42, 'updatedAt': ''},
        ]);
      }
      return jsonBody(<String, Object?>{});
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api2 = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api2),
      jobsClientProvider.overrideWith(_NoopJobs.new),
    ]);
    container.read(jobsClientProvider.notifier).attachApi(api2);
    addTearDown(container.dispose);

    await pumpDropdown(tester);
    await tester.tap(find.byIcon(LucideIcons.activity));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ЛИМИТЫ API'), findsOneWidget);
    expect(find.text('Shikimori'), findsOneWidget);
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('Не ограничен'), findsOneWidget);
    // remaining 25/90 → 28%.
    expect(find.text('28%'), findsOneWidget);
    // reset через 42 сек.
    expect(find.textContaining('42'), findsOneWidget);
  });

  testWidgets('«Открыть окно процессов» → jobsClient.openModal(jobs)',
      (tester) async {
    await pumpDropdown(tester);
    await tester.tap(find.byIcon(LucideIcons.activity));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Открыть окно процессов'));
    await tester.pump(const Duration(milliseconds: 300));
    final jobs = container.read(jobsClientProvider);
    expect(jobs.isModalOpen, isTrue);
    expect(jobs.modalTab, JobsModalTab.jobs);
  });
}
