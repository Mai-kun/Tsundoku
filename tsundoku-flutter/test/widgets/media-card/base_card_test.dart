import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton, PointerDeviceKind;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/context_menu_controller.dart';
import 'package:tsundoku_flutter/widgets/media-card/base_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';

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

MediaItem bookItem() => MediaItem.fromJson(const {
      'id': 'm1',
      'type': 'book',
      'title': 'Норагами',
      'status': 2,
      'score': 8,
      'createdAt': '2024-01-01T00:00:00Z',
    });

/// Widget-тесты `BaseCard.svelte`: тап/клавиатура → onOpen, hover-свап слоёв,
/// префетч на hover, контекст-меню, удаление через confirm, deleteError-alert.
void main() {
  late ProviderContainer container;
  late StubAdapter adapter;
  var openCount = 0;
  MediaItem? openedItem;
  final statusCalls = <MediaStatus>[];
  var deleteCount = 0;
  Object? deleteError;

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 450,
            child: BaseCard(
              props: MediaCardProps(
                item: bookItem(),
                showProgress: true,
                onOpen: (i) {
                  openCount += 1;
                  openedItem = i;
                },
                onStatusChange: (i, s) => statusCalls.add(s),
                onDelete: (i) async {
                  deleteCount += 1;
                  if (deleteError != null) throw deleteError!;
                },
              ),
              hover: const SizedBox(key: Key('hover-layer')),
              children: const SizedBox(key: Key('passive')),
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
    ]);
    addTearDown(container.dispose);
    openCount = 0;
    openedItem = null;
    statusCalls.clear();
    deleteCount = 0;
    deleteError = null;
  });

  testWidgets('рендерит пассивный слой, timeHint-чип, бейджи статуса/оценки',
      (tester) async {
    final item = bookItem();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 450,
            child: BaseCard(
              props: MediaCardProps(
                item: item,
                timeHint: const CardTimeHint(
                    label: 'осталось ~2 ч', canFinishNow: true),
              ),
              hover: null,
              children: const SizedBox(key: Key('passive')),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('passive')), findsOneWidget);
    expect(find.text('осталось ~2 ч'), findsOneWidget);
    // Бейджи из MediaPoster: статус-иконка planned bookmark + score 8.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('тап → onOpen(item)', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byType(BaseCard));
    expect(openCount, 1);
    expect(openedItem?.id, 'm1');
  });

  testWidgets('hover: passive-слой гаснет, hover-слой появляется',
      (tester) async {
    await pumpCard(tester);
    final center = tester.getCenter(find.byType(BaseCard));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();

    final opacities = tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((o) => o.opacity)
        .toList();
    expect(opacities, contains(0)); // passive скрыт
    expect(opacities, contains(1)); // hover показан
  });

  testWidgets('hover → hover-префетч детали через 150ms', (tester) async {
    await pumpCard(tester);
    final center = tester.getCenter(find.byType(BaseCard));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(
      adapter.seen.any((o) => o.path.contains('/api/media/m1')),
      isTrue,
      reason: 'hover запускает schedulePrefetchMediaDetail(item.id)',
    );
  });

  testWidgets('правый клик → контекст-меню с полным набором пунктов',
      (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byType(BaseCard), buttons: kSecondaryButton);
    await tester.pump();

    final state = container.read(contextMenuStoreProvider);
    expect(state.isOpen, isTrue);
    final ids = state.items.map((i) => i.id).toList();
    expect(ids, containsAll([
      'edit',
      'status',
      'add-to-list',
      'copy-title',
      'separator-poster',
      'open-title-folder',
      'separator1',
      'delete',
    ]));
    // delete: danger + holdToDelete (hold = подтверждение).
    final delete = state.items.firstWhere((i) => i.id == 'delete');
    expect(delete.kind, 'danger');
    expect(delete.holdToDelete, isTrue);
    // status-подменю: 4 пункта (onHold в меню отсутствует — 1-в-1).
    final statusItem = state.items.firstWhere((i) => i.id == 'status');
    expect(statusItem.children, hasLength(4));
  });

  testWidgets('статус-пункт подменю → onStatusChange(item, completed)',
      (tester) async {
    final item = bookItem().copyWithFields(status: MediaStatus.inProgress);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Center(
          child: BaseCard(
            props: MediaCardProps(
              item: item,
              onStatusChange: (i, s) => statusCalls.add(s),
            ),
            hover: null,
            children: const SizedBox(),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(BaseCard), buttons: kSecondaryButton);
    await tester.pump();

    final state = container.read(contextMenuStoreProvider);
    final statusItem = state.items.firstWhere((i) => i.id == 'status');
    final completed = statusItem.children!
        .firstWhere((c) => c.id == 'status-completed');
    completed.action!();
    await tester.pump();
    expect(statusCalls, [MediaStatus.completed]);
  });

  testWidgets('кнопка удаления на карточке отсутствует; удаление работает через контекст-меню',
      (tester) async {
    await pumpCard(tester);
    final center = tester.getCenter(find.byType(BaseCard));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Удалить')), findsNothing);

    await tester.tap(find.byType(BaseCard), buttons: kSecondaryButton);
    await tester.pump();
    final state = container.read(contextMenuStoreProvider);
    final deleteItem = state.items.firstWhere((i) => i.id == 'delete');
    await Future<void>.sync(() => deleteItem.action!());
    await tester.pumpAndSettle();
    expect(deleteCount, 1);
  });

  testWidgets('ошибка удаления через контекст-меню → alert-оверлей с errorMessage',
      (tester) async {
    deleteError = Exception('boom');
    await pumpCard(tester);

    await tester.tap(find.byType(BaseCard), buttons: kSecondaryButton);
    await tester.pump();
    final state = container.read(contextMenuStoreProvider);
    final deleteItem = state.items.firstWhere((i) => i.id == 'delete');
    await Future<void>.sync(() => deleteItem.action!());
    await tester.pumpAndSettle();

    // Alert-оверлей: без текста Exception — errors.unexpected.
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(
      texts.any((t) => t.data != null && t.data != 'Норагами' && t.data != '8'),
      isTrue,
      reason: 'alert содержит локализованное сообщение',
    );
  });

  testWidgets('Enter на фокусированной карточке → onOpen', (tester) async {
    await pumpCard(tester);
    // Мой Focus — единственный в поддереве BaseCard (traversal-группы — выше).
    // Focus.of ищет предка: контекст берём из виджета ПОД Focus.
    final focusFinder = find.descendant(
        of: find.byType(BaseCard), matching: find.byType(Focus)).first;
    final innerContext = tester.element(find
        .descendant(of: focusFinder, matching: find.byType(GestureDetector))
        .first);
    Focus.of(innerContext).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(openCount, 1);
  });
}
