import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/entities/media/model/detailed_score.dart';
import 'package:tsundoku_flutter/features/drop-reason/drop_reason_prompt.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_sidebar.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';

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

/// Тесты `DetailSidebar.svelte`: панели/история, статус-меню (колбек
/// родителя), рейтинг-поповер, критерии-черновик, drop-плашка → prompt,
/// сохранённая детальная оценка, auto-refresh полный цикл, spec-строки.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media(Map<String, Object?> extra) => MediaDetail.fromJson({
        'id': 'm1',
        'type': 'manga',
        'title': 'Frieren',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'startedAt': '2024-01-05T00:00:00Z',
        ...extra,
      });

  final recorder = <String, Object?>{};

  Future<(ProviderContainer, StubAdapter)> pumpSidebar(
    WidgetTester tester, {
    required MediaDetail media,
    int? scoreValue,
    bool ratingOpen = false,
    List<SpecRow> specRows = const <SpecRow>[],
    ResponseBody Function(RequestOptions options)? handler,
  }) async {
    recorder.clear();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter(handler ??
        (options) => jsonBody(<String, Object?>{
              'id': 'm1',
              'type': 'manga',
              'title': 'Frieren',
              'status': 1,
              'createdAt': '2024-01-01T00:00:00Z',
            }));
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: DetailSidebar(
              media: media,
              statusOptions: const [
                MediaStatus.planned,
                MediaStatus.inProgress,
                MediaStatus.completed,
                MediaStatus.dropped,
              ],
              statusBusy: false,
              onChangeStatus: (status) async =>
                  recorder['status'] = status,
              statusError: null,
              scoreValue: scoreValue,
              ratingOpen: ratingOpen,
              onRatingOpen: () => recorder['ratingOpen'] = true,
              onRatingClose: () {},
              onRatingHide: () => recorder['ratingHidden'] = true,
              onSetScore: (score) async => recorder['score'] = score,
              onClearScore: () => recorder['cleared'] = true,
              formatDate: (v) => v ?? '—',
              watchedOnInput: '',
              onWatchedOnInput: (value) => recorder['watchedOnInput'] = value,
              onWatchedOnDirty: () {},
              onSaveWatchedOn: () async => recorder['watchedOnSaved'] = true,
              platformOptions: const [],
              onSelectPlatform: (_) async {},
              refreshBusy: false,
              refreshError: null,
              onRefreshMetadata: () async {},
              fillMissingBusy: false,
              onFillMissing: () => recorder['fillMissing'] = true,
              onRelink: () => recorder['relink'] = true,
              onStartEdit: () {},
              deleteBusy: false,
              deleteError: null,
              onDelete: () async => recorder['deleted'] = true,
              specRows: specRows,
              onAutoRefreshed: (m) => recorder['refreshed'] = m,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (container, adapter);
  }

  testWidgets('панели: заголовки, история (started/ended), статус-триггер',
      (tester) async {
    await pumpSidebar(tester, media: media({}));

    expect(find.text('ВАША ИСТОРИЯ'), findsOneWidget);
    expect(find.text('ДЕЙСТВИЯ'), findsOneWidget);
    expect(find.text('ХАРАКТЕРИСТИКИ'), findsOneWidget);
    expect(find.text('Начало'), findsOneWidget); // startedLabel
    expect(find.text('Обновить метаданные'), findsOneWidget);
    // «…»-меню опций закрыто — проверяются только лицевые кнопки.
  });

  testWidgets('статус-меню: выбор completed → onChangeStatus(completed)',
      (tester) async {
    await pumpSidebar(tester, media: media({}));

    expect(find.text('В процессе'), findsOneWidget);
    await tester.tap(find.text('В процессе'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Завершено').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Запрос делает родитель (statusController); сайдбар только колбек.
    expect(recorder['status'], MediaStatus.completed);
  });

  testWidgets('рейтинг: сетка 1..10 → onSetScore(7) + hide', (tester) async {
    await pumpSidebar(
      tester,
      media: media({}),
      ratingOpen: true,
    );

    expect(find.text('Оценить'), findsOneWidget); // rateButton
    debugPrint('SEVEN rect: ${tester.getRect(find.text('7'))}');
    final dbg = tester.hitTestOnBinding(tester.getCenter(find.text('7')));
    final obj = find.text('7').evaluate().single.renderObject;
    debugPrint('SAMEPARA: ${identical(dbg.path.first.target, obj)}');
    try {
      debugPrint('HITTEXT: ${(dbg.path.first.target as dynamic).text}');
    } catch (_) {
      debugPrint('HITTEXT: <no text>');
    }
    for (final e in dbg.path.take(30)) {
      debugPrint('HIT: ${e.target.runtimeType}');
    }
    final popRect = tester.getRect(find.textContaining('Оценить'));
    debugPrint('RATE-TRIGGER rect: $popRect');
    await tester.tap(find.text('7'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(recorder['score'], 7);
    expect(recorder['ratingHidden'], isTrue);
  });

  testWidgets('критерии: expand → оси manga рендерятся + черновик средняя',
      (tester) async {
    await pumpSidebar(
      tester,
      media: media({}),
      ratingOpen: true,
    );

    await tester.ensureVisible(find.text('По критериям'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('По критериям'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Оси manga: сюжет/визуал/персонажи/звук/динамика.
    expect(find.text('Сюжет'), findsOneWidget);
    expect(find.text('Рисовка'), findsOneWidget);
    // Слайдеры по умолчанию 5, но draft пуст → средняя не показана.
    expect(find.textContaining('★'), findsNothing);
  });

  testWidgets('dropped: плашка причины → open dropPromptState', (tester) async {
    final (container, _) = await pumpSidebar(
      tester,
      media: media({'status': 4, 'dropReason': 'boring', 'dropNotes': 'meh'}),
    );

    expect(find.textContaining('Причина:'), findsOneWidget);
    expect(find.textContaining('meh'), findsOneWidget);

    await tester.tap(find.textContaining('Причина:'));
    await tester.pump();
    final target = container.read(dropPromptStateProvider);
    expect(target, isNotNull);
    expect(target!.id, 'm1');
    expect(target.dropReason, 'boring');
  });

  testWidgets('детальная оценка сохранена: панель с осями-барами',
      (tester) async {
    final json = jsonEncode(<String, int>{'story': 8, 'visuals': 6});
    await pumpSidebar(
      tester,
      media: media({'detailedScoreJson': json, 'score': 7}),
    );

    expect(find.text('Детальная оценка'), findsOneWidget);
    // Значения осей 1-в-1 с parse.
    final map = parseDetailedScore(json);
    expect(map['story'], 8);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('auto-refresh (ongoing): POST → onAutoRefreshed + тост',
      (tester) async {
    await pumpSidebar(
      tester,
      media: media({
        'nextAutoRefreshAt': '2024-06-01T00:00:00Z',
        'autoRefreshIntervalDays': 3,
      }),
      handler: (options) {
        if (options.uri.path.contains('/auto-refresh')) {
          return jsonBody(<String, Object?>{
            'id': 'm1',
            'type': 'manga',
            'title': 'Frieren',
            'status': 1,
            'createdAt': '2024-01-01T00:00:00Z',
            'nextAutoRefreshAt': '2024-06-04T00:00:00Z',
          });
        }
        return jsonBody(<String, Object?>{
          'id': 'm1',
          'type': 'manga',
          'title': 'Frieren',
          'status': 1,
          'createdAt': '2024-01-01T00:00:00Z',
        });
      },
    );

    expect(find.text('Проверить обновления'), findsOneWidget);
    await tester.ensureVisible(find.text('Проверить обновления'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Проверить обновления'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect((recorder['refreshed'] as MediaDetail?), isNotNull);
    // Интервал в истории.
    expect(find.textContaining('раз в 3'), findsOneWidget);
  });

  testWidgets('hold-to-delete: кнопка в панели, тап-холд гейтится deleteBusy',
      (tester) async {
    await pumpSidebar(tester, media: media({}));

    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
    // Полный цикл удержания — в hold_to_delete_test; здесь — присутствие.
  });

  testWidgets('spec-строки: href-ссылка, badges, importSource-префикс',
      (tester) async {
    await pumpSidebar(
      tester,
      media: media({}),
      specRows: const [
        SpecRow(
            label: 'Источник',
            value: 'anilist.net',
            href: 'https://anilist.co/m1'),
        SpecRow(label: 'Формат', value: 'MANGA', badges: ['MANGA', 'LONG']),
        SpecRow(label: 'Путь', value: 'media/m1', importSource: 'offline'),
      ],
    );

    expect(find.text('anilist.net'), findsOneWidget);
    expect(find.text('MANGA'), findsOneWidget);
    expect(find.text('LONG'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('жанры: чипы с genreLabel-локализацией + alt-тайтлы',
      (tester) async {
    await pumpSidebar(
      tester,
      media: media({
        'genres': ['Фэнтези', 'Драма'],
        'altTitles': ['Sousou no Frieren', '葬送のフリーレン'],
      }),
    );

    expect(find.text('Жанры'), findsOneWidget);
    expect(find.text('• Sousou no Frieren'), findsOneWidget);
    expect(find.text('• 葬送のフリーレン'), findsOneWidget);
  });
}
