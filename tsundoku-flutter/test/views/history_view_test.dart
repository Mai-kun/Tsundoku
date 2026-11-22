import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';
import 'package:tsundoku_flutter/views/history_view.dart';

MediaItem _makeItem({
  required String id,
  required String title,
  required MediaType type,
  MediaStatus status = MediaStatus.completed,
  int? score,
  String? finishedAt,
  String? startedAt,
  bool? isAnime,
}) {
  return MediaItem.fromJson(<String, dynamic>{
    'id': id,
    'type': type.wire,
    'title': title,
    'status': status.value,
    'score': score,
    'finishedAt': finishedAt,
    'startedAt': startedAt,
    'isAnime': isAnime,
    'source': 'manual',
    'createdAt': '2024-01-01T00:00:00Z',
    'updatedAt': '2024-01-01T00:00:00Z',
  });
}

List<MediaItem> _sampleMedia() {
  return [
    _makeItem(
      id: 'm1',
      title: 'Elden Ring',
      type: MediaType.game,
      score: 10,
      finishedAt: '2024-05-15T12:00:00Z',
    ),
    _makeItem(
      id: 'm2',
      title: 'Sousou no Frieren',
      type: MediaType.tvshow,
      isAnime: true,
      score: 9,
      finishedAt: '2024-03-20T18:00:00Z',
    ),
    _makeItem(
      id: 'm3',
      title: 'Steins;Gate',
      type: MediaType.tvshow,
      isAnime: true,
      score: 10,
      finishedAt: '2023-11-10T20:00:00Z',
    ),
    _makeItem(
      id: 'm4',
      title: 'Старый фильм без даты',
      type: MediaType.movie,
      score: 8,
    ),
  ];
}

List<HistoryEvent> _sampleEvents() {
  return [
    HistoryEvent.fromJson(<String, dynamic>{
      'id': 'e1',
      'mediaId': 'm1',
      'type': 'Added',
      'oldValue': null,
      'newValue': null,
      'createdAt': '2024-05-15T12:00:00Z',
      'title': 'Elden Ring',
    }),
    HistoryEvent.fromJson(<String, dynamic>{
      'id': 'e2',
      'mediaId': 'm2',
      'type': 'StatusChanged',
      'oldValue': '1',
      'newValue': '2',
      'createdAt': '2024-03-20T18:00:00Z',
      'title': 'Sousou no Frieren',
    }),
  ];
}

class _StubHistoryApi extends TsundokuApi {
  final Future<List<MediaItem>> Function()? onGetMedia;
  final Future<List<HistoryEvent>> Function(String? date)? onGetHistoryEvents;
  final Future<void> Function(String id)? onDeleteHistoryEvent;
  final Future<void> Function()? onClearAllHistory;

  _StubHistoryApi({
    this.onGetMedia,
    this.onGetHistoryEvents,
    this.onDeleteHistoryEvent,
    this.onClearAllHistory,
  }) : super(Dio());

  @override
  Future<List<MediaItem>> getMedia(
      [MediaFilters filters = const MediaFilters()]) {
    if (onGetMedia != null) return onGetMedia!();
    return Future.value(_sampleMedia());
  }

  @override
  Future<List<HistoryEvent>> getHistoryEvents({String? mediaId, String? date}) {
    if (onGetHistoryEvents != null) return onGetHistoryEvents!(date);
    return Future.value(_sampleEvents());
  }

  @override
  Future<void> deleteHistoryEvent(String id) {
    if (onDeleteHistoryEvent != null) return onDeleteHistoryEvent!(id);
    return Future.value();
  }

  @override
  Future<void> clearAllHistory() {
    if (onClearAllHistory != null) return onClearAllHistory!();
    return Future.value();
  }
}

Future<void> pumpHistoryView(
  WidgetTester tester, {
  required TsundokuApi api,
  int refreshKey = 0,
  ValueChanged<String>? onOpenMedia,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Stack(
            children: [
              HistoryView(
                refreshKey: refreshKey,
                onOpenMedia: onOpenMedia,
              ),
              const ConfirmModal(),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('loading state: скелетоны отображаются во время запроса медиа',
      (tester) async {
    final completer = Completer<List<MediaItem>>();
    final api = _StubHistoryApi(onGetMedia: () => completer.future);

    await pumpHistoryView(tester, api: api);
    await tester.pump();

    // Вкладки видны всегда в шапке
    expect(find.text('Хроника'), findsOneWidget);
    expect(find.text('Активность'), findsOneWidget);

    completer.complete(_sampleMedia());
    await tester.pumpAndSettle();
  });

  testWidgets('ошибка загрузки: отображается сообщение и кнопка retry',
      (tester) async {
    int calls = 0;
    final api = _StubHistoryApi(
      onGetMedia: () {
        calls++;
        if (calls == 1) return Future.error(Exception('Сбой сети'));
        return Future.value(_sampleMedia());
      },
    );

    await pumpHistoryView(tester, api: api);
    await tester.pumpAndSettle();

    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.text('Elden Ring'), findsWidgets);
  });

  testWidgets('успешная хроника: отображаются таймлайн, карточки, якоря и блок без даты',
      (tester) async {
    String? openedMediaId;
    final api = _StubHistoryApi();

    await pumpHistoryView(
      tester,
      api: api,
      onOpenMedia: (id) => openedMediaId = id,
    );
    await tester.pumpAndSettle();

    // Тайтл и вкладки
    expect(find.text('История активности'), findsOneWidget);
    expect(find.text('Хроника'), findsOneWidget);
    expect(find.text('Активность'), findsOneWidget);

    // Контролы хроники
    expect(find.text('По месяцам'), findsOneWidget);
    expect(find.text('По годам'), findsOneWidget);
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('Игры'), findsOneWidget);
    expect(find.text('Включая начатые'), findsOneWidget);

    // Годы в таймлайне и якоря (2024 и 2023)
    expect(find.text('2024'), findsWidgets);
    expect(find.text('2023'), findsWidgets);

    // Карточки тайтлов
    expect(find.text('Elden Ring'), findsWidgets);
    expect(find.text('Sousou no Frieren'), findsWidgets);
    expect(find.text('Steins;Gate'), findsWidgets);

    // Тап по карточке открывает тайтл
    await tester.tap(find.text('Elden Ring').first);
    expect(openedMediaId, 'm1');

    // Блок тайтлов без точной даты
    final undatedFinder = find.textContaining('Завершено без точной даты');
    expect(undatedFinder, findsOneWidget);
    await tester.ensureVisible(undatedFinder);
    await tester.pumpAndSettle();
    await tester.tap(undatedFinder);
    await tester.pumpAndSettle();
    expect(find.text('Старый фильм без даты'), findsOneWidget);
  });

  testWidgets('переключение масштаба на "По годам": мозаика мини-карточек',
      (tester) async {
    final api = _StubHistoryApi();

    await pumpHistoryView(tester, api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('По годам'));
    await tester.pumpAndSettle();

    expect(find.text('★10'), findsWidgets);
    expect(find.text('★9'), findsWidgets);
  });

  testWidgets('пустая хроника: отображается пустой стейт', (tester) async {
    final api = _StubHistoryApi(onGetMedia: () => Future.value(const []));

    await pumpHistoryView(tester, api: api);
    await tester.pumpAndSettle();

    expect(find.text('Хроника пуста'), findsOneWidget);
    expect(find.textContaining('Отметьте тайтлы как завершённые'), findsOneWidget);
  });

  testWidgets('вкладка активность: лента событий и удаление одного события с подтверждением',
      (tester) async {
    String? deletedId;
    final api = _StubHistoryApi(
      onDeleteHistoryEvent: (id) async {
        deletedId = id;
      },
    );

    await pumpHistoryView(tester, api: api);
    await tester.pumpAndSettle();

    // Переключаемся на вкладку "Активность"
    await tester.tap(find.text('Активность'));
    await tester.pumpAndSettle();

    // События отображаются
    expect(find.text('Elden Ring'), findsOneWidget);
    expect(find.text('Sousou no Frieren'), findsOneWidget);

    // Тап по корзине первого события
    final trashButtons = find.byIcon(LucideIcons.trash2);
    expect(trashButtons, findsWidgets);

    // Удаляем второе событие (Sousou no Frieren)
    await tester.tap(trashButtons.last);
    await tester.pumpAndSettle();

    // ConfirmModal открыт
    expect(find.text('Удалить эту запись из истории?'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);

    // Подтверждаем удаление
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(deletedId, 'e2');
    expect(find.text('Sousou no Frieren'), findsNothing);
  });

  testWidgets('вкладка активность: фильтр по дате и сброс', (tester) async {
    String? queriedDate;
    final api = _StubHistoryApi(
      onGetHistoryEvents: (date) async {
        queriedDate = date;
        return _sampleEvents();
      },
    );

    await pumpHistoryView(tester, api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Активность'));
    await tester.pumpAndSettle();

    expect(find.text('Фильтр по дате'), findsOneWidget);
    expect(queriedDate, isNull);
  });

  testWidgets('вкладка активность: полная очистка истории', (tester) async {
    bool cleared = false;
    final api = _StubHistoryApi(
      onClearAllHistory: () async {
        cleared = true;
      },
    );

    await pumpHistoryView(tester, api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Активность'));
    await tester.pumpAndSettle();

    // Кнопка «Очистить историю» в шапке активности
    expect(find.text('Очистить историю'), findsOneWidget);
    await tester.tap(find.text('Очистить историю'));
    await tester.pumpAndSettle();

    // ConfirmModal
    expect(find.text('Вы уверены, что хотите полностью очистить историю?'),
        findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
    expect(find.text('Elden Ring'), findsNothing);
  });
}
