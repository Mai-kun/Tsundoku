import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/settings/tabs/storage_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/ui/button.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.contains('/api/settings/storage')) {
      if (options.method == 'POST') {
        return ResponseBody.fromString(
          jsonEncode({'restartScheduled': false}),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'mode': 'default',
          'defaultDirectory': '/home/user/.tsundoku',
          'portableDirectory': '/home/user/app/data',
          'customPath': null,
          'isFirstRunSetupRequired': false,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/search-cache')) {
      if (options.method == 'DELETE') {
        return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
      }
      return ResponseBody.fromString(
        jsonEncode({
          'entryCount': 42,
          'fileSizeBytes': 10240,
          'imageFileCount': 10,
          'imageFileSizeBytes': 20480,
          'databasePath': '/home/user/.tsundoku/search_cache.db',
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/franchises/reindex')) {
      return ResponseBody.fromString(
        jsonEncode({
          'scannedCount': 15,
          'updatedCount': 3,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({_CapturingAdapter? adapter}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
      home: const Scaffold(
        body: Stack(
          children: [
            StorageTab(),
            ConfirmModal(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('StorageTab loads and renders modes, paths, cache info and buttons', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Место хранения данных'), findsWidgets);
    expect(find.text('По умолчанию (системная папка)'), findsOneWidget);
    expect(find.text('Рядом с программой (portable)'), findsOneWidget);
    expect(find.text('Свой путь'), findsOneWidget);

    expect(find.text('/home/user/.tsundoku'), findsWidgets);
    expect(find.text('/home/user/app/data'), findsOneWidget);

    expect(find.text('Пересканировать франшизы'), findsOneWidget);
    expect(find.text('Кэш поисковых запросов'), findsOneWidget);
    expect(find.textContaining('42 записей, 10 картинок'), findsOneWidget);
  });

  testWidgets('StorageTab switches to custom mode and saves settings', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Select "Свой путь"
    await tester.tap(find.text('Свой путь'));
    await tester.pumpAndSettle();

    // Enter custom path
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '/mnt/storage/tsundoku');
    await tester.pumpAndSettle();

    // Tap save
    await tester.tap(find.text('Сохранить и перезапустить'));
    await tester.pumpAndSettle();

    final postReq = adapter.requests.firstWhere(
      (r) => r.path.contains('/api/settings/storage') && r.method == 'POST',
    );
    final data = postReq.data is Map ? postReq.data as Map : jsonDecode(postReq.data.toString()) as Map;
    expect(data['mode'], 'custom');
    expect(data['customPath'], '/mnt/storage/tsundoku');
  });

  testWidgets('StorageTab triggers franchise rescan and search cache clear', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Rescan franchises
    await tester.tap(find.text('Запустить сканирование'));
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/franchises/reindex')), isTrue);

    // Clear search cache -> opens confirm dialog
    final clearBtn = find.text('Очистить кэш поиска');
    await tester.ensureVisible(clearBtn);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    // Dialog should show up
    expect(find.textContaining('Очистить кэш поисковых запросов?'), findsOneWidget);

    // Confirm inside dialog
    final modalConfirmBtn = find.widgetWithText(TsundokuButton, 'Очистить кэш поиска');
    expect(modalConfirmBtn, findsOneWidget);
    await tester.tap(modalConfirmBtn);
    await tester.pumpAndSettle();

    // DELETE request dispatched
    expect(
      adapter.requests.any((r) => r.path.contains('/api/settings/search-cache') && r.method == 'DELETE'),
      isTrue,
    );
  });
}
