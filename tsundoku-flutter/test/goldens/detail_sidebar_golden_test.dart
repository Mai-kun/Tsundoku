import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_sidebar.dart';

class StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'id': 'm1',
          'type': 'manga',
          'title': 'Frieren',
          'status': 1,
          'createdAt': '2024-01-01T00:00:00Z',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
  }

  @override
  void close({bool force = false}) {}
}

// Golden для DetailSidebar.svelte: базовое состояние сайдбара
// (история, действия, характеристики). Эталонного Svelte-скриншота нет —
// self-backstop.
void main() {
  testWidgets('detail_sidebar golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);

    final media = MediaDetail.fromJson(<String, Object?>{
      'id': 'm1',
      'type': 'manga',
      'title': 'Frieren',
      'status': 1,
      'createdAt': '2024-01-01T00:00:00Z',
      'startedAt': '2024-01-05T00:00:00Z',
      'nextAutoRefreshAt': '2024-06-01T00:00:00Z',
      'autoRefreshIntervalDays': 3,
      'detailedScoreJson': jsonEncode(<String, int>{'story': 8, 'visuals': 6}),
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: DetailSidebar(
              media: media,
              statusOptions: const [
                MediaStatus.planned,
                MediaStatus.inProgress,
                MediaStatus.completed,
                MediaStatus.dropped,
              ],
              statusBusy: false,
              onChangeStatus: (_) async {},
              statusError: null,
              scoreValue: 7,
              ratingOpen: false,
              onRatingOpen: () {},
              onRatingClose: () {},
              onRatingHide: () {},
              onSetScore: (_) async {},
              onClearScore: () {},
              formatDate: (v) => v ?? '—',
              watchedOnInput: '2024-01-05',
              onWatchedOnInput: (_) {},
              onWatchedOnDirty: () {},
              onSaveWatchedOn: () async {},
              platformOptions: const ['PC', 'Mobile'],
              onSelectPlatform: (_) async {},
              refreshBusy: false,
              refreshError: null,
              onRefreshMetadata: () async {},
              fillMissingBusy: false,
              onFillMissing: () {},
              onRelink: () {},
              onStartEdit: () {},
              deleteBusy: false,
              deleteError: null,
              onDelete: () async {},
              specRows: const [],
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(DetailSidebar),
      matchesGoldenFile('goldens/detail_sidebar.png'),
    );
  });
}
