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
          'anime': ['shikimori', 'anilist', 'mal'],
          'manga': ['mangalib', 'anilist'],
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
}
