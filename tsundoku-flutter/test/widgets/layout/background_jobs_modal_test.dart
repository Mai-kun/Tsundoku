import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/layout/background_jobs_modal.dart';
import 'package:tsundoku_flutter/widgets/media-detail/external_detail_modal.dart';

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

/// No-op jobs-контроллер: SSE-машина покрыта своими тестами.
class _NoopJobs extends JobsClientController {
  @override
  void connect() {}
}

/// Тесты полного цикла `BackgroundJobsModal.svelte`: очередь (прогресс/отмена),
/// review master-detail (авто-поиск, resolve/keep/merge/delete, keepAll/
/// resolveAll, hotkeys, превью ExternalDetailModal) + unit-тесты чистых
/// функций скоринга/сортировки/ETA.
void main() {
  late StubAdapter adapter;
  late ProviderContainer container;
  // Мутируемый handler: тесты переключают поведение посреди теста без
  // пересоздания dio/контейнера.
  ResponseBody Function(RequestOptions options) handler =
      (options) => jsonBody(<String, Object?>{});

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    handler = (options) => jsonBody(<String, Object?>{});
    adapter = StubAdapter((options) => handler(options));
  });

  void setupApi() {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      jobsClientProvider.overrideWith(_NoopJobs.new),
    ]);
    addTearDown(container.dispose);
    // jobs-контроллер берёт api через attachApi (как App в initState);
    // warm-up read: ленивый build() иначе затёр бы стейт, установленный
    // до первого pumpWidget.
    container.read(jobsClientProvider.notifier).attachApi(api);
  }

  Map<String, Object?> pendingJson(Map<String, Object?> extra) => {
        'id': 'm1',
        'title': 'Фрирен',
        'romajiTitle': 'Frieren',
        'originalTitle': null,
        'type': 'manga',
        'isAnime': false,
        'releaseYear': 2020,
        'author': 'Yamada Kanehito',
        'currentProgress': 3,
        'totalCount': 12,
        'candidates': <Object?>[],
        ...extra,
      };

  Map<String, Object?> candidateJson(String source, String id,
      {String title = 'Frieren'}) => {
            'externalId': id,
            'externalSource': source,
            'title': title,
            'type': 'manga',
            'totalCount': 12,
            'releaseYear': 2020,
          };

  void setPending(List<Map<String, Object?>> items) {
    final matches = <PendingMatchItemDto>[
      for (final e in items)
        PendingMatchItemDto.fromJson(e as Map<String, dynamic>),
    ];
    container.read(jobsClientProvider.notifier).setPendingMatchesForTest(matches);
  }

  Future<void> pumpModal(WidgetTester tester) async {
    // Канонический desktop-вьюпорт (golden-эталон 1440×900 @ dpr 1.0):
    // review-раскладка md/xl-брейкпоинты рассчитаны на него.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BackgroundJobsModal()),
    ));
    await tester.pump();
  }

  group('unit: чистые функции', () {
    test('extractLatin/extractRussian: скобки, латиница, кириллица', () {
      expect(extractLatin('Frieren'), 'Frieren');
      expect(extractLatin('Фрирен (Frieren)'), 'Frieren');
      expect(extractLatin('Фрирен'), isNull);
      expect(extractLatin(''), isNull);
      expect(extractRussian('Фрирен (Frieren)'), 'Фрирен');
      expect(extractRussian('Frieren'), 'Frieren'); // нет кириллицы → trim
      expect(extractRussian('Фрирен'), 'Фрирен');
    });

    test('scoreCandidate: direct-url 100, точное совпадение, клампы', () {
      final item =
          PendingMatchItemDto.fromJson(pendingJson({}) as Map<String, dynamic>);
      final exact = ExternalMedia.fromJson(
          candidateJson('anilist', 'a1') as Map<String, dynamic>);
      // Точное совпадение (60) + год (20) + автор (15) + количество (10) = 105 → кламп 100.
      expect(scoreCandidate(item, exact), 100);

      final direct = ExternalMedia.fromJson({
        ...candidateJson('anilist', 'a1'),
        'title': 'Совсем другое название',
        'isDirectUrl': true,
      } as Map<String, dynamic>);
      expect(scoreCandidate(item, direct), 100);

      final noMatch = ExternalMedia.fromJson({
        ...candidateJson('anilist', 'a1'),
        'title': 'ZZZ Unrelated',
      } as Map<String, dynamic>);
      expect(scoreCandidate(item, noMatch), 0);
    });

    test('sortCandidates: приоритет источника, внутри — скоринг', () {
      final item =
          PendingMatchItemDto.fromJson(pendingJson({}) as Map<String, dynamic>);
      final kitsu = ExternalMedia.fromJson(
          candidateJson('kitsu', 'k1', title: 'Frieren') as Map<String, dynamic>);
      final anilist = ExternalMedia.fromJson(
          candidateJson('anilist', 'a1', title: 'Фрирен') as Map<String, dynamic>);
      final sorted =
          sortCandidates([kitsu, anilist], item, const {});
      expect(sorted.first.externalSource, 'anilist'); // приоритет выше
    });

    test('stepCounts/etaMinutes/isBatchImport', () {
      final counts = stepCounts('[12/377] Title (авто)');
      expect(counts, isNotNull);
      expect(counts!.current, 12);
      expect(counts.total, 377);
      expect(stepCounts('Syncing'), isNull);
      // (377-12)*2.5/60 = 15.2 → ceil 16.
      final job = JobProgress.fromJson({
        'jobId': 'j1',
        'title': 'Импорт списка',
        'progressPercent': 3,
        'currentStep': '[12/377] Title',
        'status': 'Running',
        'startedAt': '2024-01-01T00:00:00Z',
      } as Map<String, dynamic>);
      expect(etaMinutes(job), 16);
      expect(isBatchImport(job), isTrue);
      final queued = JobProgress.fromJson({
        'jobId': 'j2',
        'title': 'Sync',
        'progressPercent': 0,
        'currentStep': 'waiting',
        'status': 'Queued',
        'startedAt': '2024-01-01T00:00:00Z',
      } as Map<String, dynamic>);
      expect(isBatchImport(queued), isFalse);
    });
  });

  group('widget: таб «Очередь»', () {
    testWidgets('пустая очередь → empty state', (tester) async {
      setupApi();
      await pumpModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('Нет активных задач'), findsOneWidget);
    });

    testWidgets('задача: название, %, cancel → DELETE job', (tester) async {
      setupApi();
      container.read(jobsClientProvider.notifier).applyJson(jsonEncode({
        'jobId': 'j1',
        'title': 'Sync anime: Frieren',
        'progressPercent': 45,
        'currentStep': 'Fetching episodes',
        'status': 'Running',
        'startedAt': '2024-01-01T00:00:00Z',
      }));
      await pumpModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('Sync anime: Frieren'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('Отменить задачу'), findsOneWidget); // cancellable

      // cancel → DELETE /api/jobs/j1 (проверка по seen).
      await tester.tap(find.text('Отменить задачу'));
      await tester.pumpAndSettle();
      expect(adapter.seen.any((o) => o.path.contains('/api/jobs/j1')), isTrue);
    });

    testWidgets('banner при pending>0: gotoReview переключает таб',
        (tester) async {
      setupApi();
      setPending([pendingJson({})]);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('сомневается'), findsOneWidget); // banner
      expect(find.text('Требуют уточнения'), findsOneWidget); // review tab

      await tester.tap(find.text('Перейти к выбору →'));
      await tester.pumpAndSettle();
      expect(
          container.read(jobsClientProvider).modalTab, JobsModalTab.review);
    });
  });

  group('widget: review master-detail', () {
    testWidgets('строка без кандидатов: авто-поиск по romaji + карточки '
        'кандидатов с бейджем источника и match-баллом', (tester) async {
      handler = (options) {
        if (options.path == '/api/external/search') {
          expect(options.queryParameters['source'], 'anilist'); // топ-приоритет
          expect(options.queryParameters['query'], 'Frieren'); // romaji
          return jsonBody([
            candidateJson('anilist', 'a1'),
            candidateJson('kitsu', 'k1', title: 'Frieren: KN'),
          ]);
        }
        return jsonBody(<String, Object?>{});
      };
      setupApi();
      setPending([pendingJson({})]);
      container
          .read(jobsClientProvider.notifier)
          .setModalTab(JobsModalTab.review);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      // Master list: заголовок + тип + счётчик кандидатов.
      expect(find.text('Фрирен'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // счётчик кандидатов + [ 1 / 2 ]
      // Detail: карточки кандидатов (название + бейдж источника + балл);
      // «Frieren» также в двух поисковых полях (query pre-fill) → 3.
      expect(find.text('Frieren'), findsNWidgets(3));
      expect(find.text('Frieren: KN'), findsOneWidget);
      expect(find.text('anilist'), findsOneWidget); // бейдж источника — сырое имя
      expect(find.textContaining('%'), findsWidgets); // match-баллы
    });

    testWidgets('resolve: POST resolve-match с payload, строка уходит, '
        'тост', (tester) async {
      handler = (options) {
        if (options.path == '/api/external/search') {
          return jsonBody([candidateJson('anilist', 'a1')]);
        }
        if (options.path.contains('/api/media/m1/resolve-match')) {
          expect(options.method, 'POST');
          return jsonBody({
            'id': 'm1',
            'type': 'manga',
            'title': 'Frieren',
            'status': 1,
            'createdAt': '2024-01-01T00:00:00Z',
          });
        }
        return jsonBody(<String, Object?>{});
      };
      setupApi();
      setPending([pendingJson({}), pendingJson({'id': 'm2', 'title': 'Вторая'})]);
      container
          .read(jobsClientProvider.notifier)
          .setModalTab(JobsModalTab.review);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();

      expect(
          adapter.seen
              .any((o) => o.path.contains('/api/media/m1/resolve-match')),
          isTrue);
      // Строка ушла из ревью (dropPendingMatch), осталась вторая.
      expect(container.read(jobsClientProvider).pendingMatches.length, 1);
      // Тост подтверждения — через стор (ToastContainer в тесте не смонтирован).
      final toasts = container.read(toastStoreProvider);
      expect(toasts.any((t) => t.title.isNotEmpty), isTrue);
    });

    testWidgets('keepAll: POST dismiss-all-matches + тост с количеством',
        (tester) async {
      setupApi();
      setPending([pendingJson({}), pendingJson({'id': 'm2', 'title': 'Вторая'})]);
      container
          .read(jobsClientProvider.notifier)
          .setModalTab(JobsModalTab.review);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Оставить все'));
      await tester.pumpAndSettle();

      expect(
          adapter.seen.any((o) => o.path.contains('/dismiss-all-matches')),
          isTrue);
      expect(container.read(jobsClientProvider).pendingMatches, isEmpty);
      final toasts = container.read(toastStoreProvider);
      expect(toasts.any((t) => t.title.contains('2')), isTrue); // keptToast(2)
    });

    testWidgets('duplicate-вердикт: intro + merge → POST merge-duplicate',
        (tester) async {
      setupApi();
      setPending([
        pendingJson({
          'duplicate': {
            'conflictType': 'same_source',
            'existingMediaId': 'm9',
            'existingTitle': 'Фрирен (существующая)',
            'incomingTitle': 'Фрирен',
          },
        }),
      ]);
      container
          .read(jobsClientProvider.notifier)
          .setModalTab(JobsModalTab.review);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('существующая'), findsOneWidget); // intro
      // Merge → POST /api/media/m9/merge-duplicate/m1.
      handler = (options) {
        if (options.path.contains('/merge-duplicate/')) {
          expect(options.method, 'POST');
          return jsonBody({
            'id': 'm9',
            'type': 'manga',
            'title': 'Фрирен',
            'status': 1,
            'createdAt': '2024-01-01T00:00:00Z',
          });
        }
        return jsonBody(<String, Object?>{});
      };
      await tester.tap(find.text('Объединить источники'));
      await tester.pumpAndSettle();

      expect(
          adapter.seen.any((o) => o.path.contains('/api/media/m9/merge-duplicate/m1')),
          isTrue);
      expect(container.read(jobsClientProvider).pendingMatches, isEmpty);
    });

    testWidgets('hotkeys: S — skip (selection двигается), Delete — '
        'deleteMedia', (tester) async {
      handler = (options) {
        if (options.path == '/api/external/search') {
          return jsonBody([candidateJson('anilist', 'a1')]);
        }
        if (options.method == 'DELETE' && options.path.contains('/api/media/')) {
          return jsonBody(<String, Object?>{});
        }
        return jsonBody(<String, Object?>{});
      };
      setupApi();
      setPending([pendingJson({}), pendingJson({'id': 'm2', 'title': 'Вторая'})]);
      container
          .read(jobsClientProvider.notifier)
          .setModalTab(JobsModalTab.review);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      // S: skip → выделение на второй строке.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(find.text('Вторая'), findsWidgets); // в master-list и detail

      // Delete: удалить текущую строку.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
          adapter.seen.any((o) =>
              o.method == 'DELETE' && o.path.contains('/api/media/m2')),
          isTrue);
    });

    testWidgets('превью: «Подробнее» открывает ExternalDetailModal, '
        'кнопка-действие резолвит кандидата', (tester) async {
      handler = (options) {
        if (options.path == '/api/external/search') {
          return jsonBody([
            candidateJson('anilist', 'a1'),
          ]);
        }
        if (options.path == '/api/external/details') {
          return jsonBody({
            'externalId': 'a1',
            'externalSource': 'anilist',
            'title': 'Frieren',
            'type': 'manga',
            'description': 'Подробное описание превью',
          });
        }
        if (options.path.contains('/resolve-match')) {
          return jsonBody({
            'id': 'm1',
            'type': 'manga',
            'title': 'Frieren',
            'status': 1,
            'createdAt': '2024-01-01T00:00:00Z',
          });
        }
        return jsonBody(<String, Object?>{});
      };
      setupApi();
      setPending([pendingJson({})]);
      container
          .read(jobsClientProvider.notifier)
          .setModalTab(JobsModalTab.review);
      await pumpModal(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Подробнее'));
      await tester.pumpAndSettle();

      // ExternalDetailModal отрисован поверх.
      expect(find.byType(ExternalDetailModal), findsOneWidget);
      expect(find.text('Подробное описание превью'), findsOneWidget);

      // Choose из actions превью → resolve + закрытие превью
      // (в карточке кандидата тоже есть «Выбрать» — ищем внутри превью).
      final previewChoose = find.descendant(
          of: find.byType(ExternalDetailModal), matching: find.text('Выбрать'));
      await tester.ensureVisible(previewChoose);
      await tester.tap(previewChoose);
      await tester.pumpAndSettle();

      expect(find.byType(ExternalDetailModal), findsNothing);
      expect(
          adapter.seen.any((o) => o.path.contains('/resolve-match')), isTrue);
    });
  });
}
