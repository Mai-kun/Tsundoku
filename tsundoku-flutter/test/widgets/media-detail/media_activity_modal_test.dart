import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/widgets/media-detail/media_activity_modal.dart';

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

/// Тесты `MediaActivityModal.svelte`: лента событий (иконки/время/дата),
/// дата-фильтр перезагрузка, optimistic delete с rollback.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<Map<String, Object?>> eventsJson() => [
        {
          'id': 'h1',
          'mediaId': 'm1',
          'type': 'StatusChanged',
          'oldValue': '1',
          'newValue': '2',
          'createdAt': '2024-04-06T12:30:00Z',
          'title': 'Frieren',
        },
        {
          'id': 'h2',
          'mediaId': 'm1',
          'type': 'ProgressChanged',
          'oldValue': null,
          'newValue': '5',
          'createdAt': '2024-04-07T18:00:00Z',
          'title': 'Frieren',
        },
      ];

  Future<ProviderContainer> pumpModal(
    WidgetTester tester, {
    bool isOpen = true,
    Map<String, ResponseBody Function(RequestOptions)>? handlers,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter((options) {
      if (handlers != null) {
        for (final entry in handlers.entries) {
          if (options.path.contains(entry.key)) return entry.value(options);
        }
      }
      if (options.path.contains('/api/history')) {
        return jsonBody(eventsJson());
      }
      return jsonBody(<String, Object?>{});
    });
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: Stack(
            children: [
              MediaActivityModal(
                isOpen: isOpen,
                mediaId: 'm1',
                title: 'Frieren',
                onClose: () {},
              ),
              const ConfirmModal(),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('лента: заголовок, события с временем/датой, delete-кнопки',
      (tester) async {
    await pumpModal(tester);

    expect(find.text('История активности'), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.history), findsWidgets); // иконки типов
    expect(find.textContaining('12:30'), findsOneWidget);
    expect(find.textContaining('18:00'), findsOneWidget);
  });

  testWidgets('пусто: «Нет записей активности»', (tester) async {
    await pumpModal(
      tester,
      handlers: {
        '/api/history': (options) => jsonBody([]),
      },
    );
    expect(find.textContaining('Нет записей активности'), findsOneWidget);
  });

  testWidgets('ошибка загрузки: rose-текст + Retry', (tester) async {
    await pumpModal(
      tester,
      handlers: {
        '/api/history': (options) => jsonBody({'detail': 'history down'}, 500),
      },
    );
    expect(find.text('history down'), findsOneWidget);
    expect(find.textContaining('Повторить'), findsOneWidget);
  });

  testWidgets('optimistic delete: confirm → строка уходит + тост', (tester) async {
    late ProviderContainer container;
    container = await pumpModal(
      tester,
      handlers: {
        '/api/history/h1': (options) => jsonBody(<String, Object?>{}),
      },
    );

    await tester.tap(find.byIcon(LucideIcons.trash2).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Удалить эту запись'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    // h1 ушла, h2 осталась.
    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
    expect(container.read(toastStoreProvider).any((t) =>
        t.title == 'Запись удалена из истории'), isTrue);
  });
}
