import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/settings/tabs/search_tab.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final bool includeOfflineInPriority;
  final List<Map<String, dynamic>> offlineDatabases;

  _CapturingAdapter({
    this.includeOfflineInPriority = false,
    this.offlineDatabases = const [],
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.contains('/api/settings/category-order')) {
      if (options.method == 'PUT') {
        final body = options.data is List ? options.data as List : jsonDecode(options.data.toString()) as List;
        return ResponseBody.fromString(
          jsonEncode(body),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode(['anime', 'manga', 'movie', 'tvshow', 'game', 'book']),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/navigation-categories')) {
      if (options.method == 'PUT') {
        final body = options.data is Map
            ? options.data as Map
            : jsonDecode(options.data.toString()) as Map;
        final list = body['categories'] as List? ?? [];
        return ResponseBody.fromString(
          jsonEncode(list),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode([
          {
            'id': 'light-novels',
            'label': 'Ранобэ',
            'icon': 'sparkle',
            'parentType': 'Book',
            'matchKind': 'format',
            'matchValue': 'light_novel',
          },
        ]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/source-priority')) {
      if (options.method == 'PUT') {
        final body = options.data is Map ? options.data as Map : jsonDecode(options.data.toString()) as Map;
        return ResponseBody.fromString(
          jsonEncode(body),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'anime': includeOfflineInPriority
              ? ['shikimori', 'offline', 'anilist', 'mal']
              : ['shikimori', 'anilist', 'mal'],
          'manga': ['mangalib', 'anilist'],
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/offline-databases')) {
      return ResponseBody.fromString(
        jsonEncode({
          'databases': offlineDatabases,
          'totalIndexedTitles': offlineDatabases.isEmpty ? 0 : 1200,
          'offlineDirectoryPath': '/data/offline',
          'pendingDumps': <String>[],
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/offline-mode')) {
      return ResponseBody.fromString(
        jsonEncode({
          'offlineMode': false,
          'hasDatabases': offlineDatabases.isNotEmpty,
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    if (path.contains('/api/settings/sources')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 'shikimori', 'name': 'Shikimori', 'description': '', 'mediaTypes': ['anime'], 'requiresApiKey': false, 'optionalApiKey': false, 'isConfigured': true, 'hasKey': false, 'maskedKey': null, 'isEnabled': true, 'isScraper': false, 'isProxied': false},
          {'id': 'anilist', 'name': 'AniList', 'description': '', 'mediaTypes': ['anime', 'manga'], 'requiresApiKey': false, 'optionalApiKey': false, 'isConfigured': true, 'hasKey': false, 'maskedKey': null, 'isEnabled': true, 'isScraper': false, 'isProxied': false},
          {'id': 'mal', 'name': 'MyAnimeList', 'description': '', 'mediaTypes': ['anime'], 'requiresApiKey': false, 'optionalApiKey': false, 'isConfigured': true, 'hasKey': false, 'maskedKey': null, 'isEnabled': true, 'isScraper': false, 'isProxied': false},
          {'id': 'mangalib', 'name': 'MangaLib', 'description': '', 'mediaTypes': ['manga'], 'requiresApiKey': false, 'optionalApiKey': false, 'isConfigured': true, 'hasKey': false, 'maskedKey': null, 'isEnabled': true, 'isScraper': true, 'isProxied': false},
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

Widget _buildSubject({_CapturingAdapter? adapter}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(tokens: TsundokuTheme.obsidian),
      home: const Scaffold(
        body: SearchTab(),
      ),
    ),
  );
}

void main() {
  testWidgets('SearchTab renders category order, promoted categories and source priority', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // 1. Category Order
    expect(find.text('Порядок категорий в поиске «Все»'), findsOneWidget);
    expect(find.text('Аниме'), findsWidgets);
    expect(find.text('Манга'), findsWidgets);

    // 2. Promoted Categories
    expect(find.text('Вынесенные категории сайдбара'), findsOneWidget);
    expect(find.text('Комиксы'), findsOneWidget); // Preset button
    expect(find.text('Ранобэ'), findsWidgets); // Active item

    // 3. Source Priority
    expect(find.text('Приоритет источников по типам'), findsOneWidget);
    expect(find.text('Shikimori'), findsOneWidget);
    expect(find.text('AniList'), findsWidgets);
    expect(find.text('Основной'), findsWidgets);
  });

  testWidgets('SearchTab moves category down and sends save request', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Click move down for the first category (Anime)
    final downButtons = find.byIcon(LucideIcons.chevronDown);
    expect(downButtons, findsWidgets);
    await tester.tap(downButtons.first);
    await tester.pumpAndSettle();

    // Verify PUT request
    final req = adapter.requests.firstWhere(
      (r) => r.path.contains('/api/settings/category-order') && r.method == 'PUT',
    );
    final data = req.data as List;
    expect(data.first, 'manga');
    expect(data[1], 'anime');
  });

  testWidgets('SearchTab adds preset promoted subcategory and deletes it', (tester) async {
    final adapter = _CapturingAdapter();
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // Tap preset "Комиксы"
    final comicsPreset = find.text('Комиксы');
    expect(comicsPreset, findsOneWidget);
    await tester.tap(comicsPreset);
    await tester.pumpAndSettle();

    // Verify PUT navigation-categories request with comics added
    final putReq = adapter.requests.firstWhere(
      (r) => r.path.contains('/api/settings/navigation-categories') && r.method == 'PUT',
    );
    final data = (putReq.data as Map)['categories'] as List;
    expect(data.any((c) => (c as Map)['id'] == 'comics'), isTrue);

    // Delete "Ранобэ"
    final trashIcons = find.byIcon(LucideIcons.trash2);
    expect(trashIcons, findsWidgets);
    await tester.tap(trashIcons.first);
    await tester.pumpAndSettle();

    // Verify deletion request
    final deletePutReq = adapter.requests.lastWhere(
      (r) => r.path.contains('/api/settings/navigation-categories') && r.method == 'PUT',
    );
    final deleteData = (deletePutReq.data as Map)['categories'] as List;
    expect(deleteData.any((c) => (c as Map)['id'] == 'light-novels'), isFalse);
  });

  testWidgets('SearchTab supports drag-and-drop on category order and source priority with 2-column layout', (tester) async {
    final adapter = _CapturingAdapter();
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    // 2-column check: "АНИМЕ" and "МАНГА" category headers share the same vertical row
    final animeHeader = find.text('АНИМЕ');
    final mangaHeader = find.text('МАНГА');
    expect(animeHeader, findsOneWidget);
    expect(mangaHeader, findsOneWidget);
    expect(tester.getTopLeft(animeHeader).dy, closeTo(tester.getTopLeft(mangaHeader).dy, 2.0));
    expect(tester.getTopLeft(mangaHeader).dx, greaterThan(tester.getTopLeft(animeHeader).dx));

    // Drag first category ("Аниме") down below second ("Манга") using grip handle
    final firstGrip = find.byIcon(LucideIcons.gripVertical).first;
    await tester.drag(firstGrip, const Offset(0, 65));
    await tester.pumpAndSettle();

    final catPut = adapter.requests.lastWhere(
      (r) => r.path.contains('/api/settings/category-order') && r.method == 'PUT',
    );
    final catOrder = catPut.data as List;
    expect(catOrder[0], 'manga');
    expect(catOrder[1], 'anime');

    // Drag first source priority item ("Shikimori") down onto "AniList"
    final shikiCenter = tester.getCenter(find.text('Shikimori'));
    final anilistCenter = tester.getCenter(find.text('AniList').first);
    await tester.timedDrag(
      find.text('Shikimori'),
      Offset(0, (anilistCenter.dy - shikiCenter.dy) + 12),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    final prioPut = adapter.requests.lastWhere(
      (r) => r.path.contains('/api/settings/source-priority') && r.method == 'PUT',
    );
    final prioMap = prioPut.data as Map;
    expect((prioMap['anime'] as List)[0], 'anilist');
    expect((prioMap['anime'] as List)[1], 'shikimori');
  });

  testWidgets('SearchTab hides Offline Database from source priority when no offline databases exist', (tester) async {
    final adapter = _CapturingAdapter(
      includeOfflineInPriority: true,
      offlineDatabases: const [],
    );
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Shikimori'), findsOneWidget);
    expect(find.text('Offline Database'), findsNothing);
    expect(find.text('offline'), findsNothing);
  });

  testWidgets('SearchTab shows Offline Database in source priority when offline databases exist', (tester) async {
    final adapter = _CapturingAdapter(
      includeOfflineInPriority: true,
      offlineDatabases: const [
        {
          'name': 'Anime Offline',
          'fileName': 'anime.db',
          'type': 'anime',
          'totalTitles': 1200,
          'fileSizeBytes': 1024,
          'lastModified': '2026-01-01T00:00:00Z',
          'isActive': true,
        },
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1440, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    expect(find.text('Offline Database'), findsOneWidget);
  });
}
