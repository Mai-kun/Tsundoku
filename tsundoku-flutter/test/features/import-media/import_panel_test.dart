import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/import-media/import_panel.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Object?> bodies = [];

  RequestOptions? get lastImportRequest =>
      requests.where((r) => r.path.contains('/api/media/import')).lastOrNull;

  Object? get lastImportBody {
    final idx = requests.lastIndexWhere((r) => r.path.contains('/api/media/import'));
    return idx != -1 ? bodies[idx] : null;
  }

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    bodies.add(options.data);

    final path = options.uri.path;
    if (path.contains('/api/lists')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 'l1', 'name': 'Избранное', 'itemCount': 5},
          {'id': 'l2', 'name': 'Очередь', 'itemCount': 10},
        ]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/sources')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 'steam', 'name': 'Steam', 'hasKey': true},
          {'id': 'mangalib', 'name': 'MangaLib', 'hasKey': false},
        ]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/media/import')) {
      return ResponseBody.fromString(
        jsonEncode({
          'totalFound': 15,
          'importedCount': 12,
          'skippedDuplicates': 3,
          'targetListId': 'l1',
          'targetListName': 'Избранное',
          'skippedTitles': ['Duplicate Title 1', 'Duplicate Title 2'],
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{}),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  VoidCallback? onImportCompleted,
  ValueChanged<String>? onNavigateToList,
  VoidCallback? onClose,
  bool showCloseButton = false,
  _CapturingAdapter? adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ImportPanel(
              onImportCompleted: onImportCompleted,
              onNavigateToList: onNavigateToList,
              onClose: onClose,
              showCloseButton: showCloseButton,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders all 9 providers in selector', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('MangaLib'), findsOneWidget);
    expect(find.text('MyAnimeList'), findsOneWidget);
    expect(find.text('Shikimori'), findsOneWidget);
    expect(find.text('Letterboxd'), findsOneWidget);
    expect(find.text('Goodreads'), findsOneWidget);
    expect(find.text('Steam'), findsOneWidget);
    expect(find.text('Anixart'), findsOneWidget);
    expect(find.text('CSV / JSON'), findsOneWidget);
  });

  testWidgets('switches to Steam provider and shows Steam inputs',
      (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Steam'));
    await tester.pumpAndSettle();

    expect(find.text('Steam профиль'), findsOneWidget);
    expect(find.text('Steam ID или ссылка на профиль'), findsOneWidget);
    expect(find.text('Steam Web API Key (опционально)'), findsOneWidget);
    expect(find.text('Пропускать игры с временем < 2 часов'), findsOneWidget);
  });

  testWidgets('validates empty username for AniList and performs import',
      (tester) async {
    final adapter = _CapturingAdapter();
    var importCompleted = false;

    await tester.pumpWidget(_buildSubject(
      onImportCompleted: () => importCompleted = true,
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    // Click import with empty username
    await tester.tap(find.text('Начать импорт'));
    await tester.pumpAndSettle();

    expect(find.text('Введите никнейм пользователя AniList.'), findsOneWidget);

    // Enter username
    await tester.enterText(
        find.widgetWithText(TextField, 'Никнейм AniList'), 'Mai-kun');
    await tester.pumpAndSettle();

    // Click import again
    await tester.tap(find.text('Начать импорт'));
    await tester.pumpAndSettle();

    expect(adapter.lastImportRequest?.path,
        contains('/api/media/import/anilist-profile'));
    expect(adapter.lastImportBody, {
      'username': 'Mai-kun',
      'createList': false,
      'targetListId': null,
      'newListName': null,
      'skipDuplicates': true,
    });
    expect(importCompleted, isTrue);

    // Check results view
    expect(find.text('Импорт завершён'), findsOneWidget);
    expect(find.text('12'), findsOneWidget); // importedCount
    expect(find.text('3'), findsOneWidget); // skippedDuplicates
  });

  testWidgets('Steam profile import sends correct payload', (tester) async {
    final adapter = _CapturingAdapter();

    await tester.pumpWidget(_buildSubject(adapter: adapter));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Steam'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Steam ID или ссылка на профиль'),
        '76561198000000001');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Начать импорт'));
    await tester.pumpAndSettle();

    expect(
        adapter.lastImportRequest?.path, contains('/api/media/import/steam'));
    expect(adapter.lastImportBody, {
      'steamId': '76561198000000001',
      'profileUrl': null,
      'steamApiKey': null,
      'skipDuplicates': true,
      'targetListId': null,
      'newListName': null,
      'minPlaytimeMinutes': 120,
      'syncAchievements': true,
    });
  });

  testWidgets('toggles addToList and shows new list text field',
      (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Название нового списка'), findsNothing);

    // Tap checkbox
    await tester.tap(find.text('Добавить импортированные тайтлы в список'));
    await tester.pumpAndSettle();

    expect(find.text('Название нового списка'), findsOneWidget);
  });
}
