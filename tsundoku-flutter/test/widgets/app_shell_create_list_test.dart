import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/lists/create_list_modal.dart';
import 'package:tsundoku_flutter/features/lists/list_picker.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/ui/context_menu_controller.dart';
import 'package:tsundoku_flutter/widgets/layout/app_shell.dart';

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

void main() {
  late ProviderContainer container;
  late StubAdapter adapter;
  var createdList = false;
  var listsCallCount = 0;

  setUp(() {
    createdList = false;
    listsCallCount = 0;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) {
      if (options.method == 'POST' && options.path == '/api/lists') {
        createdList = true;
        return jsonBody({'id': 'l-new'});
      }
      if (options.method == 'GET' && options.path == '/api/lists') {
        listsCallCount++;
        return jsonBody([
          if (createdList)
            {
              'id': 'l-new',
              'name': 'Новый 2026',
              'itemsCount': 0,
              'color': '#473bb8',
              'updatedAt': '2026-11-22T00:00:00Z',
              'isSmart': false,
            },
        ]);
      }
      if (options.path.contains('/api/media/m1/lists')) {
        return jsonBody(<String>[]);
      }
      if (options.path == '/api/media') {
        return jsonBody(<dynamic>[]);
      }
      return jsonBody(<String, Object?>{});
    });

    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('AppShell: нажатие «+ Новый список» открывает CreateListModal и сохранение обновляет список', (tester) async {
    // Активируем ListPicker в AppShell для mediaId 'm1'
    container.read(activeListPickerMediaIdProvider.notifier).set('m1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: AppShell(
          sidebar: SizedBox(),
          header: SizedBox(),
          child: Text('Main Content'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Проверяем, что ListPicker открыт
    expect(find.byType(ListPicker), findsOneWidget);
    expect(find.text('+ Новый список'), findsOneWidget);

    // Нажимаем «+ Новый список»
    await tester.tap(find.text('+ Новый список'));
    await tester.pumpAndSettle();

    // Должна открыться модалка создания списка
    expect(find.byType(CreateListModal), findsOneWidget);

    // Вводим название нового списка в первый TextField
    final nameField = find.byType(TextField).first;
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Новый 2026');
    await tester.pumpAndSettle();

    // Нажимаем «Создать список» на кнопке ElevatedButton
    final btn = find.widgetWithText(ElevatedButton, 'Создать список');
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    // Модалка закрылась
    expect(find.byType(CreateListModal), findsNothing);

    // Списки обновились через refreshLists (listsCallCount >= 2)
    expect(createdList, isTrue);
    expect(listsCallCount, greaterThanOrEqualTo(2));
    expect(find.text('Новый 2026'), findsOneWidget);
  });
}
