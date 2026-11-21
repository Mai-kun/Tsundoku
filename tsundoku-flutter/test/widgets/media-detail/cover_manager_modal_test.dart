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
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/widgets/media-detail/cover_manager_modal.dart';

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

/// Тесты `CoverManagerModal.svelte`: галерея/активная обложка, add by URL
/// (payload + тост + onUpdate), выбор, удаление с подтверждением, volumes
/// (manga), легаси-фолбэк, inline-ошибка.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<Map<String, Object?>> coversJson() => [
        {
          'id': 'c1',
          'thumbUrl': '/media-assets/m1/covers/c1/thumb.webp',
          'originalUrl': '/media-assets/m1/covers/c1/original.webp',
          'source': 'AniList',
          'addedAt': '2024-01-02T00:00:00Z',
        },
        {
          'id': 'c2',
          'thumbUrl': '/media-assets/m1/covers/c2/thumb.webp',
          'originalUrl': '/media-assets/m1/covers/c2/original.webp',
          'source': null,
          'addedAt': '2024-01-03T00:00:00Z',
        },
      ];

  MediaDetail media({
    List<Map<String, Object?>>? covers,
    String? coverUrl,
    String type = 'manga',
  }) =>
      MediaDetail.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'Frieren',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'coverUrl': ?coverUrl,
        'covers': ?covers,
      });

  /// Обновлённый detail, который сервер возвращает на мутации.
  Map<String, Object?> updatedJson({
    List<Map<String, Object?>>? covers,
    String? coverUrl,
  }) =>
      {
        'id': 'm1',
        'type': 'manga',
        'title': 'Frieren',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'coverUrl': coverUrl ?? '/media-assets/m1/covers/c1/thumb.webp',
        'covers': covers ?? coversJson(),
      };

  Future<ProviderContainer> pumpModal(
    WidgetTester tester, {
    required MediaDetail media,
    ResponseBody Function(RequestOptions options)? handler,
    void Function(MediaDetail updated)? onUpdate,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter(
        handler ?? (options) => jsonBody(updatedJson()));
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: CoverManagerModal(
            isOpen: true,
            media: media,
            onClose: () {},
            onUpdate: onUpdate ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('галерея: заголовок, счётчик, активный бейдж, delete-кнопки',
      (tester) async {
    await pumpModal(tester,
        media: media(covers: coversJson(), coverUrl: coversJson()[0]['thumbUrl'] as String));

    expect(find.text('Управление обложками'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // счётчик
    expect(find.text('Активная'), findsOneWidget); // c1 активная
    expect(find.byIcon(LucideIcons.trash2), findsNWidgets(2));
    // Бейдж источника рендерится по hover — но в дереве всегда (opacity).
    expect(find.text('AniList'), findsOneWidget);
  });

  testWidgets('add by URL: POST payload {url, setAsActive}, тост, onUpdate, очистка поля',
      (tester) async {
    final requests = <RequestOptions>[];
    MediaDetail? updated;
    final container = await pumpModal(
      tester,
      media: media(covers: coversJson()),
      handler: (options) {
        requests.add(options);
        if (options.method == 'POST' &&
            options.uri.path.endsWith('/api/media/m1/covers')) {
          return jsonBody(updatedJson());
        }
        return jsonBody(updatedJson());
      },
      onUpdate: (u) => updated = u,
    );

    await tester.enterText(
        find.byType(TextField), 'https://example.com/cover.jpg');
    await tester.pump();
    await tester.tap(find.text('Добавить').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.uri.path, '/api/media/m1/covers');
    final body = requests.single.data as Map<String, Object?>;
    expect(body['url'], 'https://example.com/cover.jpg');
    expect(body['setAsActive'], true);
    expect(updated, isNotNull);
    // Тост в сторе (ToastContainer в тесте не смонтирован).
    expect(
      container.read(toastStoreProvider).any((t) =>
          t.title.contains('Обложка добавлена') &&
          t.description.contains('готов к работе')),
      isTrue,
    );
    // Поле очищено.
    expect(find.byType(TextField), findsOneWidget);
    final controller =
        (find.byType(TextField).evaluate().single.widget as TextField)
            .controller!;
    expect(controller.text, isEmpty);
  });

  testWidgets('select: клик по неактивной плитке → PUT covers/c2/select + тост',
      (tester) async {
    final requests = <RequestOptions>[];
    MediaDetail? updated;
    final container = await pumpModal(
      tester,
      media: media(covers: coversJson(), coverUrl: coversJson()[0]['thumbUrl'] as String),
      handler: (options) {
        requests.add(options);
        return jsonBody(updatedJson(
            coverUrl: '/media-assets/m1/covers/c2/thumb.webp'));
      },
      onUpdate: (u) => updated = u,
    );

    await tester.tap(find.byKey(const ValueKey('c2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests.single.method, 'PUT');
    expect(requests.single.uri.path, '/api/media/m1/covers/c2/select');
    expect(updated, isNotNull);
    expect(
      container.read(toastStoreProvider).any((t) =>
          t.title.contains('Обложка выбрана') &&
          t.description.contains('перезагрузки')),
      isTrue,
    );
  });

  testWidgets('delete: confirm-оверлей → DELETE covers/c2 + тост + onUpdate',
      (tester) async {
    final requests = <RequestOptions>[];
    MediaDetail? updated;
    final rest = coversJson()..removeAt(1);
    final container = await pumpModal(
      tester,
      media: media(covers: coversJson(), coverUrl: coversJson()[0]['thumbUrl'] as String),
      handler: (options) {
        requests.add(options);
        if (options.method == 'DELETE') {
          return jsonBody(updatedJson(covers: rest));
        }
        return jsonBody(updatedJson());
      },
      onUpdate: (u) => updated = u,
    );

    // Кнопка delete второй плитки (trash2 × 2) — тапаем последнюю.
    await tester.tap(find.byIcon(LucideIcons.trash2).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Inline-подтверждение.
    expect(find.text('Удалить?'), findsOneWidget);

    await tester.tap(find.text('Удалить').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
    expect(requests.single.uri.path, '/api/media/m1/covers/c2');
    expect(updated, isNotNull);
    expect(
      container.read(toastStoreProvider).any((t) =>
          t.title.contains('Обложка удалена') &&
          t.description.contains('безвозвратно')),
      isTrue,
    );
    expect(find.text('Удалить?'), findsNothing);
  });

  testWidgets('fetch volumes (manga): POST covers/fetch-volumes + тост',
      (tester) async {
    final requests = <RequestOptions>[];
    MediaDetail? updated;
    final container = await pumpModal(
      tester,
      media: media(covers: coversJson()),
      handler: (options) {
        requests.add(options);
        return jsonBody(updatedJson(covers: [...coversJson(), ...coversJson()]));
      },
      onUpdate: (u) => updated = u,
    );

    await tester.tap(find.text('Обложки томов'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests.single.method, 'POST');
    expect(requests.single.uri.path, '/api/media/m1/covers/fetch-volumes');
    expect(updated, isNotNull);
    expect(
      container.read(toastStoreProvider).any((t) =>
          t.title.contains('Обложки томов загружены') &&
          t.description.contains('готов к работе')),
      isTrue,
    );
  });

  testWidgets('не-manga: кнопка «Обложки томов» скрыта', (tester) async {
    await pumpModal(tester,
        media: media(covers: coversJson(), type: 'book'));
    expect(find.text('Обложки томов'), findsNothing);
  });

  testWidgets('легаси: covers пуст, coverUrl есть — одна плитка, без empty-блока',
      (tester) async {
    await pumpModal(tester,
        media: media(coverUrl: '/media-assets/m1/cover/thumb.webp'));
    expect(find.text('Нет сохранённых обложек'), findsNothing);
    expect(find.text('Активная'), findsOneWidget);
  });

  testWidgets('ошибка сервера → inline errorMessage, поле сохраняет ввод',
      (tester) async {
    await pumpModal(
      tester,
      media: media(covers: coversJson()),
      handler: (options) =>
          jsonBody(<String, Object?>{'detail': 'boom', 'status': 500}, 500),
    );

    await tester.enterText(
        find.byType(TextField), 'https://example.com/cover.jpg');
    await tester.pump();
    await tester.tap(find.text('Добавить').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('boom'), findsOneWidget);
    final controller =
        (find.byType(TextField).evaluate().single.widget as TextField)
            .controller!;
    expect(controller.text, 'https://example.com/cover.jpg');
  });
}
