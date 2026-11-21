import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/context_menu_controller.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tsundoku_flutter/features/lists/list_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/widgets/layout/app_shell.dart';

/// Widget-тесты `AppShell.svelte`: десктоп/мобайл раскладки, оверлеи
/// (lightbox/context-menu/ListPicker/toasts), mainRef-скролл.
/// closeListPicker принимает WidgetRef; из теста — через временный
/// Consumer-виджет (riverpod: WidgetRef привязан к элементу).
void closeListPickerViaContainer(ProviderContainer container) {
  container.read(activeListPickerMediaIdProvider.notifier).set(null);
}

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    // Списки пусты: ListPicker-оверлей открывается без контента.
    if (options.path.contains('/api/lists')) {
      return ResponseBody.fromString(jsonEncode([]), 200,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString(jsonEncode(<String, Object?>{}), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = _StubAdapter();
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AppShell(
          sidebar: const SizedBox(key: Key('sidebar'), width: 200, height: 40),
          header: const SizedBox(key: Key('header')),
          child: const SizedBox(key: Key('content')),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('десктоп: сайдбар 240px слева, header h-14, контент справа',
      (tester) async {
    await pumpShell(tester, size: const Size(1440, 900));
    final sidebar = tester.getRect(find.byKey(const Key('appshell-sidebar')));
    expect(sidebar.width, 240);
    expect(sidebar.left, 0);
    expect(sidebar.height, 900);
    // header h-14 на верху main-области.
    final header = tester.getRect(find.byKey(const Key('appshell-header')));
    expect(header.left, 240);
    expect(header.height, 56);
  });

  testWidgets('мобайл: рельса снизу, header сверху', (tester) async {
    await pumpShell(tester, size: const Size(500, 900));
    final sidebar = tester.getRect(find.byKey(const Key('appshell-sidebar')));
    expect(sidebar.bottom, 900); // fixed bottom-0
    expect(sidebar.height, 57); // py-2(16) + рельса h-10(40) + border-t(1)
    final header = tester.getRect(find.byKey(const Key('appshell-header')));
    expect(header.top, 0);
    expect(header.height, 56);
  });

  testWidgets('ListPicker открывается по activeListPickerMediaId',
      (tester) async {
    await pumpShell(tester);
    expect(find.byType(ListPicker), findsNothing);

    container.read(activeListPickerMediaIdProvider.notifier).set('m1');
    await tester.pump();
    expect(find.byType(ListPicker), findsOneWidget);

    // Закрытие через closeListPicker.
    closeListPickerViaContainer(container);
    await tester.pump();
    expect(find.byType(ListPicker), findsNothing);
    // Флаш dio-таймеров открытой загрузки (invariant pending timers).
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('p-6 padding вокруг контента (без noPadding)', (tester) async {
    await pumpShell(tester, size: const Size(1440, 900));
    final main = tester.getRect(find.byKey(const Key('appshell-main')));
    expect(main.left, 240);
    final content = tester.getRect(find.byKey(const Key('content')));
    // p-6 = 24px внутри main (контент центрируется в колонке — важен верх).
    expect(content.top, 56 + 24); // header 56 + p-6
    expect(content.left, greaterThan(240));
  });
}
