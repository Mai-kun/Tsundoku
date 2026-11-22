import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/settings/tabs/sources_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

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

    if (path.contains('/api/settings/offline-databases/reindex')) {
      return ResponseBody.fromString('', 200, headers: {Headers.contentTypeHeader: ['application/json']});
    }

    if (path.contains('/api/settings/offline-databases')) {
      return ResponseBody.fromString(
        jsonEncode({
          'totalIndexedTitles': 12500,
          'offlineDirectoryPath': '/data/offline',
          'pendingDumps': ['anime_raw.json'],
          'databases': [
            {
              'name': 'Manga Offline DB',
              'fileName': 'manga.db',
              'type': 'manga',
              'totalTitles': 8500,
              'fileSizeBytes': 15728640,
              'lastModified': '2026-11-20T12:00:00Z',
              'isActive': true,
              'sourceDumpFileName': null,
            },
            {
              'name': 'Anime Offline DB',
              'fileName': 'anime.db',
              'type': 'anime',
              'totalTitles': 4000,
              'fileSizeBytes': 8388608,
              'lastModified': '2026-11-20T12:00:00Z',
              'isActive': false,
              'sourceDumpFileName': 'anime_raw.json',
            },
          ],
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/offline-mode')) {
      if (options.method == 'POST') {
        final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
        return ResponseBody.fromString(
          jsonEncode(body['enabled'] == true),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode({'offlineMode': false, 'hasDatabases': true}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/proxy/test')) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'latencyMs': 85,
          'message': 'OK',
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/proxy')) {
      if (options.method == 'PUT') {
        final data = options.data as Map<String, dynamic>;
        return ResponseBody.fromString(
          jsonEncode({
            'enabled': data['enabled'] ?? true,
            'hasPassword': data['password'] != null,
            'maskedPassword': data['password'] != null ? '****' : null,
            'proxiedSources': data['proxiedSources'] ?? [],
          }),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'enabled': false,
          'proxyUrl': 'http://127.0.0.1:8080',
          'username': 'proxy_user',
          'hasPassword': true,
          'maskedPassword': '****',
          'proxiedSources': ['shikimori'],
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/sources/') && path.contains('/test')) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'latencyMs': 45,
          'message': 'Connected',
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/sources/') && path.contains('/toggle')) {
      final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
      return ResponseBody.fromString(
        jsonEncode({'isEnabled': body['enabled'] ?? true}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/sources/') && path.contains('/key')) {
      final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
      final key = body['apiKey'] as String? ?? '';
      return ResponseBody.fromString(
        jsonEncode({
          'hasKey': key.isNotEmpty,
          'maskedKey': key.isNotEmpty ? 'sk_live_****' : null,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/sources/') && path.contains('/proxy')) {
      final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
      return ResponseBody.fromString(
        jsonEncode({
          'isProxied': body['isProxied'] ?? true,
          'proxiedSources': ['shikimori', 'anilist'],
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/sources')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'id': 'anilist',
            'name': 'AniList',
            'description': 'Anime and manga database',
            'mediaTypes': ['anime', 'manga'],
            'requiresApiKey': true,
            'optionalApiKey': false,
            'isConfigured': true,
            'hasKey': true,
            'maskedKey': 'al_tok_****',
            'isEnabled': true,
            'isScraper': false,
            'isProxied': false,
          },
          {
            'id': 'mangalib',
            'name': 'MangaLib',
            'description': 'Manga catalog and reader',
            'mediaTypes': ['manga'],
            'requiresApiKey': false,
            'optionalApiKey': false,
            'isConfigured': true,
            'hasKey': false,
            'maskedKey': null,
            'isEnabled': true,
            'isScraper': true,
            'isProxied': false,
          },
        ]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  _CapturingAdapter? adapter,
  void Function(String sourceId, String? type)? onTestSearch,
}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
      home: Scaffold(
        body: SourcesTab(onTestSearch: onTestSearch),
      ),
    ),
  );
}

void main() {
  testWidgets('SourcesTab renders Layer 0 offline databases, proxy block and sources', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Check Layer 0 block header
    expect(find.text('Локальные офлайн-базы (Layer 0)'), findsOneWidget);
    expect(find.text('12500 тайтлов'), findsOneWidget);
    expect(find.text('Manga Offline DB'), findsOneWidget);
    expect(find.text('Anime Offline DB'), findsOneWidget);

    // Check Proxy block
    expect(find.text('Сеть и прокси'), findsOneWidget);
    expect(find.text('http://127.0.0.1:8080'), findsOneWidget);

    // Check Sources header
    expect(find.text('Поддерживаемые источники'), findsOneWidget);
    expect(find.text('Официальные API'), findsOneWidget);
    expect(find.text('Веб-парсеры сайтов'), findsOneWidget);

    // In 'api' filter, AniList should be visible, MangaLib (scraper) should not
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('MangaLib'), findsNothing);

    // Switch to Scrapers tab
    await tester.tap(find.text('Веб-парсеры сайтов'));
    await tester.pumpAndSettle();

    // Now MangaLib should be visible, AniList hidden
    expect(find.text('MangaLib'), findsOneWidget);
    expect(find.text('AniList'), findsNothing);
  });

  testWidgets('SourcesTab tests source connection and updates key', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Find Test connection button for AniList
    final testBtn = find.text('Проверить связь');
    expect(testBtn, findsOneWidget);
    await tester.tap(testBtn);
    await tester.pumpAndSettle();

    // Verify request to test connection
    expect(adapter.requests.any((r) => r.path.contains('/api/settings/sources/anilist/test')), isTrue);
    expect(find.text('Доступен (45 мс)'), findsOneWidget);

    // Enter a new API key in the field
    final keyField = find.byType(TextField).last;
    await tester.enterText(keyField, 'new_secret_key');
    await tester.pumpAndSettle();

    final saveKeyBtn = find.text('Сохранить ключ');
    expect(saveKeyBtn, findsOneWidget);
    await tester.tap(saveKeyBtn);
    await tester.pumpAndSettle();

    // Verify key save request
    final keyReq = adapter.requests.firstWhere((r) => r.path.contains('/api/settings/sources/anilist/key'));
    expect(keyReq.data, containsPair('apiKey', 'new_secret_key'));
  });

  testWidgets('SourcesTab saves proxy settings and triggers reindex', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Tap Reindex dumps
    final reindexBtn = find.text('Пересканировать дампы');
    expect(reindexBtn, findsOneWidget);
    await tester.tap(reindexBtn);
    await tester.pumpAndSettle();

    expect(adapter.requests.any((r) => r.path.contains('/api/settings/offline-databases/reindex')), isTrue);

    // Tap Save proxy button
    final saveProxyBtn = find.text('Сохранить');
    expect(saveProxyBtn, findsOneWidget);
    await tester.tap(saveProxyBtn);
    await tester.pumpAndSettle();

    expect(adapter.requests.any((r) => r.path.contains('/api/settings/proxy') && r.method == 'PUT'), isTrue);
  });
}
