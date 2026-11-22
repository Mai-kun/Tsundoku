import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/settings/tabs/backup_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/platform/platform.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class _FakePlatformService implements PlatformService {
  final List<({String suggestedName, Uint8List bytes})> savedFiles = [];
  ({String name, Uint8List bytes})? pickedFileToReturn;

  @override
  Future<void> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    savedFiles.add((suggestedName: suggestedName, bytes: bytes));
  }

  @override
  Future<({String name, Uint8List bytes})?> pickFile() async {
    return pickedFileToReturn;
  }

  @override
  Future<void> initWindow() async {}

  @override
  Future<void> copyText(String text) async {}

  @override
  Future<void> copyImagePng(Uint8List pngBytes) async {}

  @override
  Future<({Uint8List bytes, String mimeType})?> pasteImage() async => null;

  @override
  Future<void> openExternalUrl(String url) async {}

  @override
  Future<void> closeWindow() async {}
}

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

    if (path.contains('/api/settings/backup/export')) {
      final bytes = utf8.encode('dummy-zip-bytes');
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {Headers.contentTypeHeader: ['application/zip']},
      );
    }

    if (path.contains('/api/settings/export/json')) {
      final bytes = utf8.encode('{"items": []}');
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/export/csv')) {
      final bytes = utf8.encode('id,title,type\n');
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {Headers.contentTypeHeader: ['text/csv']},
      );
    }

    if (path.contains('/api/settings/backup/restore')) {
      return ResponseBody.fromString(
        '{}',
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/reset')) {
      return ResponseBody.fromString(
        '{}',
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
        body: BackupTab(),
      ),
    ),
  );
}

void main() {
  late _FakePlatformService fakePlatform;
  late PlatformService prevPlatform;

  setUp(() {
    fakePlatform = _FakePlatformService();
    prevPlatform = platformService;
    platformService = fakePlatform;
  });

  tearDown(() {
    platformService = prevPlatform;
  });

  testWidgets('BackupTab renders all 4 sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Экспорт резервной копии'), findsOneWidget);
    expect(find.text('Скачать резервную копию'), findsOneWidget);

    expect(find.text('Экспорт таблицы данных'), findsOneWidget);
    expect(find.text('Скачать JSON'), findsOneWidget);
    expect(find.text('Скачать CSV'), findsOneWidget);

    expect(find.textContaining('ВОССТАНОВЛЕНИЕ ИЗ КОПИИ'), findsOneWidget);
    expect(find.text('Восстановить из файла...'), findsOneWidget);

    expect(find.textContaining('УДАЛИТЬ ВСЕ ДАННЫЕ'), findsOneWidget);
    expect(find.text('Сбросить медиатеку...'), findsOneWidget);
  });

  testWidgets('BackupTab export buttons trigger download API requests and platform save', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // 1. Export backup
    await tester.tap(find.text('Скачать резервную копию'));
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/backup/export')), isTrue);
    expect(fakePlatform.savedFiles.any((f) => f.suggestedName.startsWith('tsundoku-backup-')), isTrue);

    // 2. Export JSON
    await tester.tap(find.text('Скачать JSON'));
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/export/json')), isTrue);
    expect(fakePlatform.savedFiles.any((f) => f.suggestedName.endsWith('.json')), isTrue);

    // 3. Export CSV
    await tester.tap(find.text('Скачать CSV'));
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/export/csv')), isTrue);
    expect(fakePlatform.savedFiles.any((f) => f.suggestedName.endsWith('.csv')), isTrue);
  });

  testWidgets('BackupTab restore flow confirms and calls restore API', (tester) async {
    final adapter = _CapturingAdapter();
    fakePlatform.pickedFileToReturn = (
      name: 'tsundoku-mybackup.zip',
      bytes: Uint8List.fromList(utf8.encode('zip-contents')),
    );

    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Tap restore
    await tester.tap(find.text('Восстановить из файла...'));
    await tester.pumpAndSettle();

    // Confirmation dialog should be shown
    expect(find.text('Подтверждение восстановления'), findsOneWidget);
    expect(find.textContaining('tsundoku-mybackup.zip'), findsOneWidget);

    // Tap confirm button
    await tester.tap(find.text('Да, восстановить базу'));
    await tester.pumpAndSettle();

    // Verify restore request was dispatched
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/backup/restore')), isTrue);
  });

  testWidgets('BackupTab reset dialog requires confirmation word before submitting', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Open Reset Dialog
    await tester.tap(find.text('Сбросить медиатеку...'));
    await tester.pumpAndSettle();

    // Verify modal elements
    expect(find.text('Полный сброс данных'), findsOneWidget);
    expect(find.text('Подтвердить полное удаление'), findsOneWidget);

    // Button should be disabled initially (not matching УДАЛИТЬ)
    final confirmButtonFinder = find.widgetWithText(ElevatedButton, 'Подтвердить полное удаление');
    ElevatedButton btn = tester.widget<ElevatedButton>(confirmButtonFinder);
    expect(btn.onPressed, isNull);

    // Enter wrong word
    await tester.enterText(find.byType(TextField), 'НЕ ТО');
    await tester.pumpAndSettle();
    btn = tester.widget<ElevatedButton>(confirmButtonFinder);
    expect(btn.onPressed, isNull);

    // Enter correct confirmation word
    await tester.enterText(find.byType(TextField), 'УДАЛИТЬ');
    await tester.pumpAndSettle();
    btn = tester.widget<ElevatedButton>(confirmButtonFinder);
    expect(btn.onPressed, isNotNull);

    // Tap confirm
    await tester.tap(confirmButtonFinder);
    await tester.pumpAndSettle();

    // Verify reset request was sent
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/reset')), isTrue);
  });
}
