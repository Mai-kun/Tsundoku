import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/images_module.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final path = options.uri.path;
    if (path.contains('/api/media/m1/covers/c1') &&
        options.method == 'DELETE') {
      return ResponseBody.fromString(
          jsonEncode(_detailPayload(covers: [], coverUrl: '')),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    if (path.contains('/api/media/m1/covers/c1')) {
      return ResponseBody.fromString(
          jsonEncode(_detailPayload(covers: [
            {
              'id': 'c1',
              'thumbUrl': 'http://x/c1.jpg',
              'originalUrl': 'http://x/c1.jpg',
              'sourceUrl': null,
              'addedAt': '2024-01-01T00:00:00Z'
            },
            {
              'id': 'c2',
              'thumbUrl': 'http://x/c2.jpg',
              'originalUrl': 'http://x/c2.jpg',
              'sourceUrl': null,
              'addedAt': '2024-01-02T00:00:00Z'
            },
          ], coverUrl: 'http://x/c1.jpg')),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    if (path.contains('/api/media/m1/covers')) {
      return ResponseBody.fromString(
          jsonEncode(_detailPayload(covers: [
            {'id': 'c2', 'thumbUrl': 'http://x/c2.jpg', 'originalUrl': 'http://x/c2.jpg', 'addedAt': '2024-01-02T00:00:00Z'},
          ], coverUrl: 'http://x/c2.jpg')),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    if (path.contains('/api/media/m1/covers/c1') && options.method == 'DELETE') {
      return ResponseBody.fromString(
          jsonEncode(_detailPayload(covers: [], coverUrl: '')),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    if (path.contains('/api/media/m1/covers/c1')) {
      return ResponseBody.fromString(
          jsonEncode(_detailPayload(covers: [
            {'id': 'c1', 'thumbUrl': 'http://x/c1.jpg', 'originalUrl': 'http://x/c1.jpg', 'addedAt': '2024-01-01T00:00:00Z'},
            {'id': 'c2', 'thumbUrl': 'http://x/c2.jpg', 'originalUrl': 'http://x/c2.jpg', 'addedAt': '2024-01-02T00:00:00Z'},
          ], coverUrl: 'http://x/c1.jpg')),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    return ResponseBody.fromString(
        jsonEncode(<String, Object?>{}), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _detailPayload({
  required List<Object?> covers,
  required String coverUrl,
}) =>
    <String, Object?>{
      'id': 'm1',
      'type': 'book',
      'title': 'Book',
      'status': 1,
      'createdAt': '2024-01-01T00:00:00Z',
      'coverUrl': coverUrl,
      'covers': covers,
    };

void main() {
  Widget wrap(Widget child, [Dio? dio]) => ProviderScope(
        overrides: dio == null
            ? const []
            : [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
        child: MaterialApp(
          theme: buildTsundokuTheme(),
          home: Material(
            child: SingleChildScrollView(
              child: SizedBox(
                width: 500,
                child: child,
              ),
            ),
          ),
        ),
      );

  testWidgets('новая запись: поле coverUrl + createModeHint', (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    await tester.pumpWidget(wrap(ImagesModule(
      mediaId: null,
      coverUrl: '',
      onCoverUrlChange: (_) {},
      title: 'Book',
      covers: const [],
      onCoversChange: (_) {},
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ModuleCard), findsOneWidget);
    expect(find.byIcon(LucideIcons.image), findsOneWidget);
    expect(find.text('Обложка'), findsOneWidget);
    expect(
        find.textContaining('станут доступны после создания записи'),
        findsOneWidget);
    expect(find.text('URL'), findsNothing); // create-режим без менеджмента
  });

  testWidgets('существующая запись: URL-поле, чекбокс, дроп-зона',
      (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    await tester.pumpWidget(wrap(ImagesModule(
      mediaId: 'm1',
      coverUrl: 'http://x/c1.jpg',
      onCoverUrlChange: (_) {},
      title: 'Book',
      covers: const [
        MediaCoverItem(
            id: 'c1',
            thumbUrl: 'http://x/c1.jpg',
            originalUrl: 'http://x/c1.jpg',
            source: null,
            sourceUrl: null,
            addedAt: '2024-01-01T00:00:00Z'),
      ],
      onCoversChange: (_) {},
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('URL'), findsOneWidget);
    expect(find.text('Сделать активной'), findsOneWidget);
    expect(find.textContaining('перетащите изображения сюда'), findsOneWidget);
    // Кнопка добавления disabled при пустом urlDraft.
    expect(find.text('Добавить обложку'), findsOneWidget);
  });

  testWidgets('добавление URL: сплит по строкам + POST + covers-change',
      (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    MediaDetail? updated;
    await tester.pumpWidget(wrap(ImagesModule(
      mediaId: 'm1',
      coverUrl: 'http://x/c1.jpg',
      onCoverUrlChange: (_) {},
      title: 'Book',
      covers: const [
        MediaCoverItem(
            id: 'c1',
            thumbUrl: 'http://x/c1.jpg',
            originalUrl: 'http://x/c1.jpg',
            source: null,
            sourceUrl: null,
            addedAt: '2024-01-01T00:00:00Z'),
      ],
      onCoversChange: (next) => updated = next,
    ), dio));
    await tester.pump(const Duration(milliseconds: 50));
    // URL-поле — первый TextField (multiline).
    await tester.enterText(find.byType(TextField).first,
        'http://x/a.jpg\nhttp://x/b.jpg');
    await tester.pump();
    expect(find.text('Добавить обложку (2)'), findsOneWidget);
    await tester.tap(find.text('Добавить обложку (2)'), warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(updated, isNotNull); // POST вернул обновлённый MediaDetail
    expect(updated!.covers, hasLength(1));
  });

  testWidgets('выбор активной обложки (тап по неактивной плитке)',
      (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    MediaDetail? updated;
    await tester.pumpWidget(wrap(ImagesModule(
      mediaId: 'm1',
      coverUrl: 'http://x/c1.jpg',
      onCoverUrlChange: (_) {},
      title: 'Book',
      covers: const [
        MediaCoverItem(
            id: 'c1',
            thumbUrl: 'http://x/c1.jpg',
            originalUrl: 'http://x/c1.jpg',
            source: null,
            sourceUrl: null,
            addedAt: '2024-01-01T00:00:00Z'),
        MediaCoverItem(
            id: 'c2',
            thumbUrl: 'http://x/c2.jpg',
            originalUrl: 'http://x/c2.jpg',
            source: null,
            sourceUrl: null,
            addedAt: '2024-01-02T00:00:00Z'),
      ],
      onCoversChange: (next) => updated = next,
    ), dio));
    await tester.pump(const Duration(milliseconds: 50));
    // c1 активна (coverUrl == thumbUrl) — бейдж «Активная».
    expect(find.text('Активная'), findsOneWidget);
    // Тап по неактивной плитке (c2) — центр второй плитки.
    final secondTile = find.byType(ClipRRect).at(1);
    await tester.tap(secondTile, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(updated, isNotNull); // selectCover вернул обновлённый MediaDetail
  });

  testWidgets('удаление обложки', (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    MediaDetail? updated;
    await tester.pumpWidget(wrap(ImagesModule(
      mediaId: 'm1',
      coverUrl: '',
      onCoverUrlChange: (_) {},
      title: 'Book',
      covers: const [
        MediaCoverItem(
            id: 'c1',
            thumbUrl: 'http://x/c1.jpg',
            originalUrl: 'http://x/c1.jpg',
            source: null,
            sourceUrl: null,
            addedAt: '2024-01-01T00:00:00Z'),
      ],
      onCoversChange: (next) => updated = next,
    ), dio));
    await tester.pump(const Duration(milliseconds: 50));
    // coverUrl пуст → ни одна не активна; тап по delete-иконке.
    expect(find.text('Активная'), findsNothing);
    await tester.tap(find.byIcon(LucideIcons.trash2), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(updated, isNotNull);
    expect(updated!.covers, isEmpty);
  });
}
