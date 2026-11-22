import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tsundoku_flutter/features/search-external/search_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class _FakeSearchAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> searchResults;
  final List<RequestOptions> requests = [];

  _FakeSearchAdapter({this.searchResults = const []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.contains('/api/settings/sources')) {
      return _jsonResponse([
        {
          'id': 'anilist',
          'name': 'AniList',
          'isEnabled': true,
          'mediaTypes': ['anime', 'manga'],
        },
        {
          'id': 'rawg',
          'name': 'RAWG',
          'isEnabled': true,
          'mediaTypes': ['game'],
        },
      ]);
    }

    if (path.contains('/api/settings/category-order')) {
      return _jsonResponse(
          ['anime', 'manga', 'movie', 'tvshow', 'game', 'book']);
    }

    if (path.endsWith('/api/media') && options.method == 'GET') {
      return _jsonResponse([]);
    }

    if (path.endsWith('/api/media') && options.method == 'POST') {
      final body = options.data is Map<String, dynamic>
          ? options.data as Map<String, dynamic>
          : <String, dynamic>{};
      return _jsonResponse({
        'id': 'created-id-123',
        'type': body['type'] ?? 'game',
        'title': body['title'] ?? 'Created Title',
        'status': body['status'] ?? 0,
        'altTitles': body['altTitles'],
        'score': null,
        'coverUrl': body['coverUrl'],
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
        'isAnime': body['isAnime'] ?? false,
      });
    }

    if (path.contains('/api/external/search')) {
      return _jsonResponse(searchResults);
    }

    if (path.contains('/api/external/details')) {
      return _jsonResponse(searchResults.isNotEmpty ? searchResults.first : {});
    }

    if (options.method == 'DELETE') {
      return _jsonResponse({'success': true});
    }

    return _jsonResponse({});
  }

  ResponseBody _jsonResponse(dynamic data, {int statusCode = 200}) {
    return ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
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
  String initialType = 'all',
  String initialQuery = '',
  _FakeSearchAdapter? adapter,
  void Function(MediaItem)? onMediaAdded,
  void Function(String)? onMediaRemoved,
  void Function(String)? onNavigateToMedia,
  VoidCallback? onClose,
  int debounceMs = 50,
}) {
  final dio = Dio();
  dio.httpClientAdapter = adapter ?? _FakeSearchAdapter();
  final api = TsundokuApi(dio);

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SearchModal(
          isOpen: isOpen,
          initialType: initialType,
          initialQuery: initialQuery,
          onClose: onClose ?? () {},
          onMediaAdded: onMediaAdded ?? (_) {},
          onMediaRemoved: onMediaRemoved,
          onNavigateToMedia: onNavigateToMedia,
          debounceMs: debounceMs,
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

    expect(find.text('Поиск тайтлов'), findsNothing);
  });

  testWidgets('renders header, inputs and empty query placeholder',
      (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: true));
    await tester.pumpAndSettle();

    expect(find.text('Внешние базы'), findsOneWidget);
    expect(find.text('Поиск тайтлов'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Введите название для поиска…'), findsOneWidget);
  });

  testWidgets('searches external and displays result cards', (tester) async {
    final adapter = _FakeSearchAdapter(
      searchResults: [
        {
          'id': 'hit-1',
          'externalId': '123',
          'title': 'Elden Ring',
          'originalTitle': 'ELDEN RING',
          'type': 'game',
          'externalSource': 'rawg',
          'rating': 9.5,
          'platform': 'PC',
          'description': 'A fantasy action-RPG.',
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(
      adapter: adapter,
      initialQuery: 'Elden',
      initialType: 'game',
      debounceMs: 10,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Elden Ring'), findsOneWidget);
    expect(find.text('A fantasy action-RPG.'), findsOneWidget);
    expect(find.text('rawg'), findsOneWidget);
    expect(find.text('9.5'), findsOneWidget);
  });

  testWidgets('clicking Add creates media and shows Added button',
      (tester) async {
    MediaItem? addedMedia;

    final adapter = _FakeSearchAdapter(
      searchResults: [
        {
          'id': 'hit-1',
          'externalId': '123',
          'title': 'Elden Ring',
          'type': 'game',
          'externalSource': 'rawg',
          'rating': 9.5,
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(
      adapter: adapter,
      initialQuery: 'Elden',
      initialType: 'game',
      onMediaAdded: (m) => addedMedia = m,
      debounceMs: 10,
    ));
    await tester.pumpAndSettle();

    final addButton = find.byIcon(LucideIcons.plus);
    expect(addButton, findsOneWidget);

    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(addedMedia, isNotNull);
    expect(addedMedia!.title, 'Elden Ring');
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowRight), findsOneWidget);
  });

  testWidgets('detects URL and displays link badge', (tester) async {
    await tester.pumpWidget(_buildSubject(
      initialQuery: 'https://myanimelist.net/anime/1/Cowboy_Bebop',
      debounceMs: 10,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ссылка'), findsOneWidget);
  });

  testWidgets('typing search query triggers ZERO GET /api/external/details calls without hover',
      (tester) async {
    final adapter = _FakeSearchAdapter(
      searchResults: [
        {
          'id': 'hit-manga-1',
          'externalId': '3829',
          'title': 'Noragami: Stray God',
          'type': 'manga',
          'externalSource': 'anilist',
          'chapters': null,
          'volumes': null,
          'author': null,
        },
        {
          'id': 'hit-manga-2',
          'externalId': '1111',
          'title': 'Noragami: Stray Stories',
          'type': 'manga',
          'externalSource': 'anilist',
          'chapters': null,
          'volumes': null,
          'author': null,
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(
      adapter: adapter,
      initialQuery: 'Noragami',
      initialType: 'manga',
      debounceMs: 10,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Noragami: Stray God'), findsOneWidget);
    expect(find.text('Noragami: Stray Stories'), findsOneWidget);

    final detailRequests = adapter.requests
        .where((r) => r.path.contains('/api/external/details'))
        .toList();
    expect(detailRequests, isEmpty,
        reason: 'Typing search query must never storm /api/external/details');
  });

  testWidgets('hovering over result card triggers prefetch after 250ms delay, cancelling on exit',
      (tester) async {
    final adapter = _FakeSearchAdapter(
      searchResults: [
        {
          'id': 'hit-manga-1',
          'externalId': '3829',
          'title': 'Noragami Stray God',
          'type': 'manga',
          'externalSource': 'anilist',
        },
      ],
    );

    await tester.pumpWidget(_buildSubject(
      adapter: adapter,
      initialQuery: 'Noragami',
      initialType: 'manga',
      debounceMs: 10,
    ));
    await tester.pumpAndSettle();

    final cardFinder = find.text('Noragami Stray God');
    expect(cardFinder, findsOneWidget);

    // Initial state: 0 details requests
    expect(
        adapter.requests
            .where((r) => r.path.contains('/api/external/details')),
        isEmpty);

    // Hover over the card
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(cardFinder));
    await tester.pump();

    // After 100ms (less than 250ms hover intent), still 0 requests
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        adapter.requests
            .where((r) => r.path.contains('/api/external/details')),
        isEmpty);

    // Move away before 250ms completes -> cancelled
    await gesture.moveTo(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        adapter.requests
            .where((r) => r.path.contains('/api/external/details')),
        isEmpty);

    // Now hover and wait full 250ms -> triggers prefetch
    await gesture.moveTo(tester.getCenter(cardFinder));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final detailRequests = adapter.requests
        .where((r) => r.path.contains('/api/external/details'))
        .toList();
    expect(detailRequests, hasLength(1));
    expect(detailRequests.first.queryParameters['id'], '3829');
  });
}
