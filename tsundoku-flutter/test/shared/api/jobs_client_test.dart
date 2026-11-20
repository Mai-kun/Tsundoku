import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';

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

JobProgress job(String id,
    {String status = 'Running', double progress = 10, String? mediaId}) {
  return JobProgress.fromJson({
    'jobId': id,
    'mediaId': mediaId,
    'title': 'Sync $id',
    'progressPercent': progress,
    'currentStep': 'Working',
    'status': status,
    'startedAt': '2026-11-21T00:00:00Z',
    'errorMessage': null,
  });
}


ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  late StubAdapter adapter;
  late TsundokuApi api;
  late ProviderContainer container;
  late JobsClientController client;

  setUp(() {
    adapter = StubAdapter((options) {
      // SSE-стрим: открытый поток без данных (тесты дёргают applyJson прямо).
      if (options.path == '/api/jobs/stream') {
        return ResponseBody.fromBytes(<int>[], 200);
      }
      if (options.path == '/api/jobs') {
        return jsonBody(<Map<String, dynamic>>[], 200);
      }
      return jsonBody(null, 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    client = container.read(jobsClientProvider.notifier);
    client.attachApi(api);
  });

  test('applyJson: добавление и замена событий (full state per event)', () {
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': 'm1', 'title': 'Sync j1',
      'progressPercent': 10, 'currentStep': 'Working', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    expect(container.read(jobsClientProvider).jobs.length, 1);
    expect(container.read(activeJobsCountProvider), 1);

    // Полное состояние события заменяет запись:
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': 'm1', 'title': 'Sync j1',
      'progressPercent': 55, 'currentStep': 'Filling', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    final jobs = container.read(jobsClientProvider).jobs;
    expect(jobs.length, 1);
    expect(jobs.single.progressPercent, 55);
    expect(jobs.single.currentStep, 'Filling');
  });

  test('битый JSON игнорируется (catch в #apply)', () {
    client.applyJson('not json at all');
    expect(container.read(jobsClientProvider).jobs, isEmpty);
  });

  test('jobFor: ищет по mediaId', () {
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': 'm-42', 'title': 'S', 'progressPercent': 1,
      'currentStep': 'W', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    expect(client.jobFor('m-42')?.jobId, 'j1');
    expect(client.jobFor('m-other'), isNull);
  });

  test('settled: переход Running→Completed вызывает onJobSettled', () {
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 10,
      'currentStep': 'W', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));

    final settledJobs = <JobProgress>[];
    final unsubscribe = client.onJobSettled(settledJobs.add);

    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 100,
      'currentStep': 'Готово', 'status': 'Completed',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    expect(settledJobs.length, 1);
    expect(settledJobs.single.status, JobStatus.completed);

    // Повторный terminal-ивент не дёргает листенер (wasTerminal = true).
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 100,
      'currentStep': 'Готово', 'status': 'Completed',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    expect(settledJobs.length, 1);

    unsubscribe();
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 10,
      'currentStep': 'W', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 100,
      'currentStep': 'Готово', 'status': 'Failed',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': 'x',
    }));
    expect(settledJobs.length, 1, reason: 'после unsubscribe листенер снят');
  });

  test('eviction: terminal job удаляется через 4s (fakeAsync)', () {
    fakeAsync((async) {
      client.applyJson(jsonEncode({
        'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 100,
        'currentStep': 'Готово', 'status': 'Completed',
        'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
      }));
      expect(container.read(jobsClientProvider).jobs.length, 1);
      async.elapse(const Duration(milliseconds: 3900));
      expect(container.read(jobsClientProvider).jobs.length, 1);
      async.elapse(const Duration(milliseconds: 200));
      expect(container.read(jobsClientProvider).jobs, isEmpty);
    });
  });

  test('safety: активный job без обновлений 70s → Failed (fakeAsync)', () {
    fakeAsync((async) {
      client.applyJson(jsonEncode({
        'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 10,
        'currentStep': 'W', 'status': 'Running',
        'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
      }));
      async.elapse(const Duration(milliseconds: 69900));
      expect(
        container.read(jobsClientProvider).jobs.single.status,
        JobStatus.running,
      );
      async.elapse(const Duration(milliseconds: 200));
      final settled = container.read(jobsClientProvider).jobs.single;
      expect(settled.status, JobStatus.failed);
      expect(settled.currentStep, 'Таймаут выполнения');
      expect(settled.errorMessage, 'Превышено время ожидания задачи');
    });
  });

  test('safety таймер отменяется при terminal-событии (fakeAsync)', () {
    fakeAsync((async) {
      client.applyJson(jsonEncode({
        'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 10,
        'currentStep': 'W', 'status': 'Running',
        'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
      }));
      client.applyJson(jsonEncode({
        'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 100,
        'currentStep': 'Готово', 'status': 'Completed',
        'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
      }));
      // Прошло больше 70s: safety-таймер снят (не было Failed-события),
      // eviction на 4s уже удалил job из очереди.
      async.elapse(const Duration(seconds: 71));
      expect(container.read(jobsClientProvider).jobs, isEmpty);
    });
  });

  test('dropPendingMatch: удаляет из списка без round trip', () async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/media/pending-matches') {
        return jsonBody([
          {'id': 'pm1', 'title': 'A', 'type': 'manga', 'candidates': []},
          {'id': 'pm2', 'title': 'B', 'type': 'game', 'candidates': []},
        ], 200);}
      return ResponseBody.fromBytes(<int>[], 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    client.attachApi(api);

    try {
      final items = await api.getPendingMatches();
      // ignore: avoid_print
      print('DIAG direct items=${items.length}');
    } catch (e) {
      // ignore: avoid_print
      print('DIAG direct error=$e');
    }
    await client.refreshPendingMatches();
    // ignore: avoid_print
    print('DIAG state=${container.read(jobsClientProvider).pendingMatches.length} seq-errors swallowed');
    expect(container.read(pendingMatchesCountProvider), 2);

    client.dropPendingMatch('pm1');
    final pending = container.read(jobsClientProvider).pendingMatches;
    expect(pending.length, 1);
    expect(pending.single.id, 'pm2');
  });

  test('refreshPendingMatches: stale-ответ не перезаписывает свежий', () async {
    var calls = 0;
    adapter = StubAdapter((options) {
      if (options.path == '/api/media/pending-matches') {
        calls += 1;
        final n = calls;
        return jsonBody([
          {'id': 'pm-$n', 'title': 'T$n', 'type': 'manga', 'candidates': []},
        ], 200);}
      return ResponseBody.fromBytes(<int>[], 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    client.attachApi(api);

    // Последовательность: первый запрос «висит», второй завершился раньше
    // (stale guard по sequence).
    final first = client.refreshPendingMatches();
    await client.refreshPendingMatches();
    expect(container.read(jobsClientProvider).pendingMatches.single.id,
        'pm-2');
    await first;
    expect(container.read(jobsClientProvider).pendingMatches.single.id,
        'pm-2', reason: 'stale первый ответ (pm-1) не должен выиграть');
  });

  test('syncJobs: локальный активный job без серверного аналога → Completed',
      () async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/jobs') {
        return jsonBody(<Map<String, dynamic>>[], 200);
      }
      return ResponseBody.fromBytes(<int>[], 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    client.attachApi(api);

    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 40,
      'currentStep': 'W', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    await client.syncJobs();
    final settled = container.read(jobsClientProvider).jobs.single;
    expect(settled.status, JobStatus.completed);
    expect(settled.progressPercent, 100);
    expect(settled.currentStep, 'Готово');
  });

  test('syncJobs: рассинхрон статуса/прогресса → серверная версия', () async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/jobs') {
        return jsonBody([
          {'jobId': 'j1', 'mediaId': null, 'title': 'S',
           'progressPercent': 90, 'currentStep': 'Final', 'status': 'Running',
           'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null},
        ], 200);}
      return ResponseBody.fromBytes(<int>[], 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    client.attachApi(api);

    client.applyJson(jsonEncode({
      'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 40,
      'currentStep': 'W', 'status': 'Running',
      'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
    }));
    await client.syncJobs();
    expect(container.read(jobsClientProvider).jobs.single.progressPercent, 90);
  });

  test('cancel: POST /api/jobs/{id}/cancel, ошибка не роняет вызов', () async {
    var cancelCalls = 0;
    adapter = StubAdapter((options) {
      if (options.path == '/api/jobs/j1/cancel') {
        cancelCalls += 1;
        return jsonBody(null, 500);
      }
      return ResponseBody.fromBytes(<int>[], 200);
    });
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    api = TsundokuApi(dio);
    client.attachApi(api);

    await client.cancel('j1');
    expect(cancelCalls, 1, reason: 'ошибка проглатывается (console.error)');
  });

  test('openModal/closeModal: стейт модалки + таб (решение #10: без history)',
      () async {
    client.openModal(JobsModalTab.review);
    expect(container.read(jobsClientProvider).isModalOpen, isTrue);
    expect(container.read(jobsClientProvider).modalTab, JobsModalTab.review);
    client.closeModal();
    expect(container.read(jobsClientProvider).isModalOpen, isFalse);
  });

  test('throttle: non-force refresh внутри 5s не ходит в сеть (fakeAsync)',
      () {
    fakeAsync((async) {
      var pendingCalls = 0;
      adapter = StubAdapter((options) {
        if (options.path == '/api/media/pending-matches') {
          pendingCalls += 1;
          return jsonBody(<Map<String, dynamic>>[], 200);}
        return ResponseBody.fromBytes(<int>[], 200);
      });
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..options.baseUrl = 'http://127.0.0.1:5150';
      api = TsundokuApi(dio);
      client.attachApi(api);

      // Явный первичный refresh (как connect() в исходнике): фиксирует
      // _pendingRefreshedAt на fake-времени.
      client.refreshPendingMatches();
      for (var i = 0; i < 20; i++) {
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
      }
      // ignore: avoid_print
      print('DIAG THROTTLE pendingCalls=$pendingCalls seen=${adapter.seen.map((o) => o.method + o.path).toList()}');
      client.applyJson(jsonEncode({
        'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 10,
        'currentStep': 'W', 'status': 'Running',
        'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
      }));
      // Первое событие → refresh throttle-нут (только что refreshing).
      // Второе событие — сразу же → throttled, в сеть не ходит.
      client.applyJson(jsonEncode({
        'jobId': 'j1', 'mediaId': null, 'title': 'S', 'progressPercent': 20,
        'currentStep': 'W', 'status': 'Running',
        'startedAt': '2026-11-21T00:00:00Z', 'errorMessage': null,
      }));
      async.flushMicrotasks();
      expect(pendingCalls, 1);
    });
  });
}
