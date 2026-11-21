import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/widgets/media-detail/tabs/gallery_tab.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// Тесты `GalleryTab.svelte`: пустая галерея, карточки + удаление через
/// confirm.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<MediaGalleryItem> gallery() => [
        MediaGalleryItem.fromJson({
          'id': 'g1',
          'thumbUrl': 'http://127.0.0.1:5150/api/media/m1/gallery/g1/thumb.webp',
          'originalUrl': '/api/media/m1/gallery/g1/image.webp',
          'title': 'Screenshot 1', 'addedAt': '2024-01-01T00:00:00Z',
        }),
      ];

  Future<ProviderContainer> pumpGallery(
    WidgetTester tester, {
    required List<MediaGalleryItem> gallery,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter((options) {
      if (options.method == 'DELETE' &&
          options.path.contains('/gallery/g1')) {
        return jsonBody(<String, Object?>{});
      }
      return jsonBody(<String, Object?>{});
    });
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: GalleryTab(mediaId: 'm1', gallery: gallery),
              ),
              const ConfirmModal(),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('пусто: «Галерея пуста…» + Image-иконка', (tester) async {
    await pumpGallery(tester, gallery: []);

    expect(find.textContaining('Галерея пуста'), findsOneWidget);
    expect(find.byIcon(LucideIcons.image), findsOneWidget);
    expect(find.textContaining('Загрузить картинку'), findsOneWidget);
    expect(find.textContaining('Ctrl+V'), findsNWidgets(2)); // hint + empty
  });

  testWidgets('карточка: thumb-картинка, delete-оверлей, confirm → DELETE',
      (tester) async {
    final container = await pumpGallery(tester, gallery: gallery());

    // Карточка рендерится с thumb-изображением (Image.network).
    expect(find.byType(Image), findsOneWidget);

    // Delete-оверлей: тап по Trash2-иконке (групп-hover в тестах — opacity
    // не мешает тапу).
    await tester.tap(find.byIcon(LucideIcons.trash2));
    await tester.pumpAndSettle();

    expect(find.textContaining('Удалить этот скриншот'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(
        container
            .read(toastStoreProvider)
            .any((t) => t.title == 'Скриншот удалён'),
        isTrue);
  });
}
