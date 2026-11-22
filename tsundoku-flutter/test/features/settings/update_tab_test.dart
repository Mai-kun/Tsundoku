import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/settings/tabs/update_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int storageCallCount = 0;
  Map<String, dynamic> updateCheckResponse = {
    'currentVersion': '1.2.0',
    'latestVersion': '1.2.0',
    'isUpdateAvailable': false,
    'canSelfUpdate': false,
    'releaseTitle': null,
    'releaseNotes': null,
    'publishedAt': null,
    'releaseUrl': null,
    'downloadUrl': null,
    'assetSizeBytes': null,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.contains('/api/settings/update/check')) {
      return ResponseBody.fromString(
        jsonEncode(updateCheckResponse),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/update/apply')) {
      return ResponseBody.fromString(
        '{}',
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/storage')) {
      return ResponseBody.fromString(
        '{}',
        storageCallCount++ == 0 ? 503 : 200,
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
        body: UpdateTab(),
      ),
    ),
  );
}

void main() {
  testWidgets('UpdateTab checks updates and displays up-to-date status', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Версия: 1.2.0'), findsOneWidget);
    expect(find.text('Установлена актуальная версия.'), findsOneWidget);
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/update/check')), isTrue);
  });

  testWidgets('UpdateTab shows available update, release notes and applies update', (tester) async {
    final adapter = _CapturingAdapter();
    adapter.updateCheckResponse = {
      'currentVersion': '1.2.0',
      'latestVersion': '1.3.0',
      'isUpdateAvailable': true,
      'canSelfUpdate': true,
      'releaseTitle': 'v1.3.0 Awesome Release',
      'releaseNotes': '- Fixed bugs\n- Added Flutter UI',
      'publishedAt': '2026-11-20',
      'releaseUrl': 'https://github.com/example/releases/tag/v1.3.0',
      'downloadUrl': null,
      'assetSizeBytes': 1024000,
    };

    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Доступна версия 1.3.0'), findsOneWidget);
    expect(find.text('- Fixed bugs\n- Added Flutter UI'), findsOneWidget);

    final applyBtn = find.text('Обновить и перезапустить');
    expect(applyBtn, findsOneWidget);

    await tester.tap(applyBtn);
    await tester.pumpAndSettle();

    expect(adapter.requests.any((r) => r.path.contains('/api/settings/update/apply')), isTrue);
  });
}
