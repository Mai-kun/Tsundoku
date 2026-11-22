import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/settings/tabs/api_tokens_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/platform/platform.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class _FakePlatformService implements PlatformService {
  String? copiedText;

  @override
  Future<void> copyText(String text) async {
    copiedText = text;
  }

  @override
  Future<void> initWindow() async {}
  @override
  Future<void> copyImagePng(Uint8List pngBytes) async {}
  @override
  Future<({Uint8List bytes, String mimeType})?> pasteImage() async => null;
  @override
  Future<void> saveFile({required String suggestedName, required Uint8List bytes}) async {}
  @override
  Future<({String name, Uint8List bytes})?> pickFile() async => null;
  @override
  Future<void> openExternalUrl(String url) async {}
  @override
  Future<void> closeWindow() async {}
}

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  List<Map<String, dynamic>> tokensList = [
    {
      'id': 'tok-1',
      'name': 'Home Assistant',
      'tokenPrefix': 'tsu_live_',
      'createdAt': '2026-11-20T10:00:00Z',
      'lastUsedAt': null,
      'expiresAt': null,
    },
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.contains('/api/settings/tokens')) {
      if (options.method == 'GET') {
        return ResponseBody.fromString(
          jsonEncode(tokensList),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      if (options.method == 'POST') {
        final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
        final res = {
          'id': 'tok-2',
          'name': body['name'],
          'tokenPrefix': 'tsu_new_',
          'rawToken': 'tsu_new_secret1234567890abcdef',
        };
        tokensList.add({
          'id': 'tok-2',
          'name': body['name'],
          'tokenPrefix': 'tsu_new_',
          'createdAt': '2026-11-22T12:00:00Z',
          'lastUsedAt': null,
          'expiresAt': null,
        });
        return ResponseBody.fromString(
          jsonEncode(res),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      if (options.method == 'DELETE') {
        tokensList.removeWhere((t) => path.endsWith('/${t['id']}'));
        return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
      }
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
        body: ApiTokensTab(),
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

  testWidgets('ApiTokensTab renders tokens list with prefix and name', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('API и персональные токены'), findsOneWidget);
    expect(find.text('Home Assistant'), findsOneWidget);
    expect(find.text('tsu_live_••••••••'), findsOneWidget);
    expect(find.text('Сгенерировать новый токен'), findsOneWidget);
  });

  testWidgets('ApiTokensTab creates token and opens reveal dialog', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Click create token button
    await tester.tap(find.text('Сгенерировать новый токен'));
    await tester.pumpAndSettle();

    expect(find.text('Новый токен доступа'), findsOneWidget);

    // Enter name
    await tester.enterText(find.byType(TextField).first, 'Telegram Bot');
    await tester.pumpAndSettle();

    // Click generate
    await tester.tap(find.text('Сгенерировать'));
    await tester.pumpAndSettle();

    // Token Reveal Modal should be visible with raw token
    expect(find.text('tsu_new_secret1234567890abcdef'), findsOneWidget);
    expect(find.text('Скопировать'), findsOneWidget);

    // Copy token
    await tester.tap(find.text('Скопировать'));
    await tester.pumpAndSettle();

    expect(fakePlatform.copiedText, 'tsu_new_secret1234567890abcdef');
    expect(find.text('Скопировано!'), findsOneWidget);

    // Close reveal modal
    await tester.tap(find.text('Я сохранил токен'));
    await tester.pumpAndSettle();

    // Verify token is now in list
    expect(find.text('Telegram Bot'), findsOneWidget);
  });

  testWidgets('ApiTokensTab revokes token after confirm dialog', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Click revoke (trash icon button)
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Отозвать токен?'), findsOneWidget);

    // Confirm revoke
    final revokeBtn = find.widgetWithText(ElevatedButton, 'Отозвать');
    expect(revokeBtn, findsOneWidget);
    await tester.tap(revokeBtn);
    await tester.pumpAndSettle();

    // Verify DELETE was dispatched
    expect(
      adapter.requests.any((r) => r.path.contains('/api/settings/tokens/tok-1') && r.method == 'DELETE'),
      isTrue,
    );
  });
}
