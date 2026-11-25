import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tsundoku_flutter/features/settings/first_run_storage_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';

class _FakeStorageAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastPostBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/api/settings/storage') &&
        options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({
          'mode': 'default',
          'defaultDirectory': '/home/user/.local/share/Tsundoku',
          'portableDirectory': '/app/data',
          'customPath': null,
          'isFirstRunSetupRequired': true,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.path.contains('/api/settings/storage') &&
        options.method == 'POST') {
      lastPostBody = options.data is Map<String, dynamic>
          ? options.data as Map<String, dynamic>
          : <String, dynamic>{};
      return ResponseBody.fromString(
        jsonEncode({'restartScheduled': false}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  bool isOpen = true,
  VoidCallback? onSaved,
  _FakeStorageAdapter? adapter,
}) {
  final dio = Dio();
  dio.httpClientAdapter = adapter ?? _FakeStorageAdapter();
  final api = TsundokuApi(dio);

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: FirstRunStorageModal(
          isOpen: isOpen,
          onSaved: onSaved,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('hides when isOpen is false', (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: false));
    await tester.pumpAndSettle();

    expect(find.text('Где хранить ваши данные?'), findsNothing);
  });

  testWidgets('loads storage settings and displays 3 options', (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: true));
    await tester.pumpAndSettle();

    expect(find.textContaining('Где хранить ваши данные?'), findsOneWidget);
    expect(find.textContaining('По умолчанию'), findsOneWidget);
    expect(find.textContaining('Рядом с программой'), findsOneWidget);
    expect(find.textContaining('Свой путь'), findsOneWidget);
    expect(find.text('/home/user/.local/share/Tsundoku'), findsOneWidget);
    expect(find.text('/app/data'), findsOneWidget);
  });

  testWidgets('selecting custom shows path input and validates emptiness',
      (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: true));
    await tester.pumpAndSettle();

    final customOption = find.textContaining('Свой путь');
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    final startButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(startButton.onPressed, isNull);

    await tester.enterText(textField, '/custom/path');
    await tester.pumpAndSettle();

    final enabledButton =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('selecting portable and saving posts correct payload',
      (tester) async {
    final adapter = _FakeStorageAdapter();
    bool savedCalled = false;

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      adapter: adapter,
      onSaved: () => savedCalled = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Рядом с программой'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(adapter.lastPostBody, isNotNull);
    expect(adapter.lastPostBody!['mode'], 'portable');
    expect(adapter.lastPostBody!['customPath'], '');
    expect(adapter.lastPostBody!['migrateExistingData'], false);
    expect(savedCalled, isTrue);
  });

  testWidgets('never shows restart spinner on open before Save is pressed',
      (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: true));
    await tester.pump();
    expect(find.text('Перезапуск сервера...'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Перезапуск сервера...'), findsNothing);
    expect(find.textContaining('По умолчанию'), findsOneWidget);
    expect(find.textContaining('Рядом с программой'), findsOneWidget);
    expect(find.textContaining('Свой путь'), findsOneWidget);
  });
}
