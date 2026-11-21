import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/lists/list_picker.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';

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

/// Тесты полного цикла `ListPicker.svelte`: загрузка списков, optimistic
/// toggle с откатом, тосты.
void main() {
  late ProviderContainer container;
  late StubAdapter adapter;

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
  });

  Widget picker({bool isOpen = true, bool showTrigger = false}) =>
      ListPicker(
        mediaId: 'm1',
        isOpen: isOpen,
        onClose: () {},
        showTrigger: showTrigger,
      );

  testWidgets('открытие: списки загружены, чекбоксы включённости', (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/lists') {
        return jsonBody([
          {
            'id': 'l1', 'name': 'Читаю', 'itemsCount': 5, 'color': '#3366ff',
            'updatedAt': '2024-01-01T00:00:00Z', 'isSmart': false,
          },
          {
            'id': 'l2', 'name': 'Брошено', 'itemsCount': 2,
            'updatedAt': '2024-01-01T00:00:00Z', 'isSmart': false,
          },
        ]);
      }
      if (options.path.contains('/api/media/m1/lists')) {
        return jsonBody(['l1']);
      }
      return jsonBody(<String, Object?>{});
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: picker()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Добавить в списки'), findsOneWidget);
    expect(find.text('Читаю'), findsOneWidget);
    expect(find.text('Брошено'), findsOneWidget);
    expect(find.textContaining('5'), findsOneWidget); // listTitles(5)
    // Чекбокс l1 включён (accent-indigo).
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('toggle: POST add → тост «Добавлено в список»', (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/lists') {
        return jsonBody([
          {
            'id': 'l1', 'name': 'Читаю', 'itemsCount': 5,
            'updatedAt': '2024-01-01T00:00:00Z', 'isSmart': false,
          },
        ]);
      }
      if (options.path.contains('/api/media/m1/lists')) {
        return jsonBody([]);
      }
      if (options.method == 'POST' && options.path.contains('/api/lists/l1/items')) {
        return jsonBody(<String, Object?>{});
      }
      return jsonBody(<String, Object?>{});
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: picker()),
    ));
    await tester.pumpAndSettle();

    // Тап по строке «Читаю» → add → тост.
    await tester.tap(find.text('Читаю'));
    await tester.pumpAndSettle();
    // Тост в сторе (ToastContainer не смонтирован в тесте).
    final toasts = container.read(toastStoreProvider);
    expect(
      toasts.any((t) => t.title.contains('Добавлено в список')),
      isTrue,
    );
    // Чекбокс стал включённым.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('toggle откат при ошибке: чекбокс возвращается + error-тост',
      (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/lists') {
        return jsonBody([
          {
            'id': 'l1', 'name': 'Читаю', 'itemsCount': 5,
            'updatedAt': '2024-01-01T00:00:00Z', 'isSmart': false,
          },
        ]);
      }
      if (options.path.contains('/api/media/m1/lists')) {
        return jsonBody([]);
      }
      // addMediaToList всегда 500.
      if (options.method == 'POST') {
        return jsonBody(<String, Object?>{'title': 'boom'}, 500);
      }
      return jsonBody(<String, Object?>{});
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: picker()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Читаю'));
    await tester.pumpAndSettle();
    // Чекбокс откатился (не включён).
    expect(find.byIcon(LucideIcons.check), findsNothing);
    // Error-тост.
    final toasts = container.read(toastStoreProvider);
    expect(toasts.any((t) => t.type == ToastType.error), isTrue);
  });

  testWidgets('пустой список → «Списков пока нет»', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: picker()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Списков пока нет'), findsOneWidget);
  });
}
