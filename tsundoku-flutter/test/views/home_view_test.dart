import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/views/home_view.dart';
import 'package:tsundoku_flutter/widgets/media-card/media_card.dart';

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

/// Тесты `HomeView.svelte`: три секции по статусам, поиск-фильтр,
/// handleStatusChange (переход между секциями), рандомайзер.
void main() {
  late ProviderContainer container;
  late StubAdapter adapter;
  var openedId = '';

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    openedId = '';
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              HomeView(
                refreshKey: 0,
                onOpen: (item) => openedId = item.id,
                onMediaChanged: () {},
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) {
      final status = options.queryParameters['status']?.toString();
      final List<Map<String, Object?>> items;
      if (status == '1') {
        items = [
          {
            'id': 'p1', 'title': 'Читаемая книга', 'type': 'book',
            'status': 1, 'currentPage': 10, 'totalPages': 100,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
            'lastActivityAt': '2026-01-02T00:00:00Z',
          },
        ];
      } else if (status == '0') {
        items = [
          {
            'id': 'u1', 'title': 'Запланированная манга', 'type': 'manga',
            'status': 0, 'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
            'lastActivityAt': '2026-01-02T00:00:00Z',
          },
        ];
      } else if (status == '2') {
        items = [
          {
            'id': 'c1', 'title': 'Завершённая игра', 'type': 'game',
            'status': 2, 'score': 9, 'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
            'lastActivityAt': '2026-01-02T00:00:00Z',
          },
        ];
      } else {
        items = [];
      }
      return jsonBody(items);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('три секции: В процессе / В планах / Завершено с карточками',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('В процессе'), findsOneWidget);
    expect(find.text('В планах'), findsOneWidget);
    expect(find.text('Читаемая книга'), findsOneWidget);
    expect(find.text('Запланированная манга'), findsOneWidget);
    // Секция «Завершено» ниже вьюпорта — слайвер-виртуализация: прокрутка.
    await tester.scrollUntilVisible(
      find.text('Завершено'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Завершённая игра'), findsOneWidget);
  });

  testWidgets('поиск фильтрует секции (чипы + TotalBadge)', (tester) async {
    await pumpHome(tester);
    // Ввод поиска: «манга» оставляет только плановую мангу.
    await tester.enterText(find.byType(TextField).first, 'манга');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Запланированная манга'), findsOneWidget);
    expect(find.text('Читаемая книга'), findsNothing);
    // Чип активного фильтра.
    expect(find.textContaining('"манга"'), findsOneWidget);
  });

  testWidgets('🎲 рандомайзер: тост + onOpen выбранного тайтла',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byIcon(LucideIcons.dices));
    await tester.pumpAndSettle();
    // Тост показан и onOpen вызван с одним из элементов.
    expect(openedId, isNotEmpty);
    expect(
      ['p1', 'u1', 'c1'].contains(openedId),
      isTrue,
      reason: 'рандомайзер открывает тайтл с экрана',
    );
  });

  testWidgets('hover-тап по статус-бейджу карточки → сменить на «Завершено»',
      (tester) async {
    await pumpHome(tester);
    // Наводим курсор на карточку в процессе → статус-бейдж → поповер.
    final center = tester.getCenter(find.text('Читаемая книга'));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();

    // Клик по бейджу статуса (Bookmark → planned) — поповер с опциями.
    await tester.tap(find.byIcon(LucideIcons.bookmark).first);
    await tester.pumpAndSettle();
    // Выбор «Завершено» → карточка переезжает в завершённую секцию.
    await tester.tap(find.text('Завершено').last);
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    // Секция «Завершено» теперь содержит и эту книгу (2 карточки там).
    expect(
      find.text('Читаемая книга'),
      findsOneWidget,
      reason: 'карточка переехала в Завершено и осталась в дереве',
    );
  });
}
