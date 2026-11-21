import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tsundoku_flutter/features/prefetch-details/external_detail_prefetch.dart';
import 'package:tsundoku_flutter/features/drop-reason/drop_reason_prompt.dart';
import 'package:tsundoku_flutter/features/prefetch-details/media_detail_prefetch.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

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

MediaDetail detail(String id, {int currentPage = 10, int totalPages = 200}) {
  return MediaDetail.fromJson({
    'id': id, 'type': 'book', 'title': 'T', 'status': 1,
    'createdAt': '2026-11-21T00:00:00Z',
    'currentPage': currentPage, 'totalPages': totalPages,
  });
}

ExternalMedia ext(String externalId, String title) {
  return ExternalMedia.fromJson({
    'externalId': externalId, 'externalSource': 'AniList', 'title': title,
    'originalTitle': null, 'romajiTitle': null, 'coverUrl': null,
    'description': null, 'trailerVideoId': null, 'releaseYear': null,
    'releaseDate': null, 'endDate': null, 'releaseStatus': null,
    'format': null, 'runtimeMinutes': null, 'type': 'anime',
    'author': null, 'studio': null, 'isbn': null, 'covers': null,
    'totalCount': null, 'chapters': null, 'volumes': null,
    'mangaFormat': null, 'countryOfOrigin': null, 'platform': null,
    'rating': null, 'ratingVotes': null, 'ratings': null, 'episodes': null,
    'genres': null, 'tags': null, 'synonyms': null,
  });
}

/// Разгон dio в fakeAsync (hover-тесты).
void drain(FakeAsync async, {Duration time = const Duration(seconds: 3)}) {
  async.elapse(time);
  for (var i = 0; i < 10; i++) {
    async.flushMicrotasks();
    async.elapse(const Duration(milliseconds: 1));
  }
}

void main() {
  late StubAdapter adapter;
  late TsundokuApi api;
  late ProviderContainer container;

  setUp(() {
    adapter = StubAdapter((options) => jsonBody(null, 404));
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  group('mediaDetailPrefetch', () {
    test('loadMediaDetail: кэширует и не ходит в сеть повторно', () async {
      var calls = 0;
      adapter = StubAdapter((options) {
        if (options.path == '/api/media/m1') {
          calls += 1;
          return jsonBody({
            'id': 'm1', 'type': 'book', 'title': 'T', 'status': 1,
            'createdAt': '2026-11-21T00:00:00Z',
            'currentPage': 10, 'totalPages': 200,
          });
        }
        return jsonBody(null);
      });
      final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      dio.httpClientAdapter = adapter;
      api = TsundokuApi(dio);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      final first = await loadMediaDetail(
          container.read(mediaDetailCacheProvider), api, 'm1');
      expect(first.currentPage, 10);
      final second = await loadMediaDetail(
          container.read(mediaDetailCacheProvider), api, 'm1');
      expect(second.id, 'm1');
      expect(calls, 1, reason: 'prefetchCache отдаёт кэш в пределах TTL');
    });

    test('updateCachedDetailProgress: патчит кэш оптимистично (полный цикл)',
        () async {
      adapter = StubAdapter((options) {
        if (options.path == '/api/media/m2') {
          return jsonBody({
            'id': 'm2', 'type': 'book', 'title': 'T', 'status': 1,
            'createdAt': '2026-11-21T00:00:00Z',
            'currentPage': 10, 'totalPages': 200,
          });
        }
        return jsonBody(null);
      });
      final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      dio.httpClientAdapter = adapter;
      api = TsundokuApi(dio);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      await loadMediaDetail(
          container.read(mediaDetailCacheProvider), api, 'm2');
      updateCachedDetailProgress(
          container.read(mediaDetailCacheProvider), 'm2', 55);

      final cached = container.read(mediaDetailCacheProvider).peek('m2')!;
      expect(cached.currentPage, 55,
          reason: 'открытие detail сразу после шага покажет новое число');
      expect(cached.totalPages, 200, reason: 'прочие поля сохранены');
    });

    test('updateCachedDetailProgress: чужой id не патчится', () async {
      adapter = StubAdapter((options) {
        if (options.path == '/api/media/m3') {
          return jsonBody({
            'id': 'm3', 'type': 'book', 'title': 'T', 'status': 1,
            'createdAt': '2026-11-21T00:00:00Z',
            'currentPage': 10, 'totalPages': 200,
          });
        }
        return jsonBody(null);
      });
      final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      dio.httpClientAdapter = adapter;
      api = TsundokuApi(dio);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      await loadMediaDetail(
          container.read(mediaDetailCacheProvider), api, 'm3');
      updateCachedDetailProgress(
          container.read(mediaDetailCacheProvider), 'other-id', 55);
      expect(
          container.read(mediaDetailCacheProvider).peek('m3')!.currentPage, 10);
    });

    test('HoverPrefetchScheduler: только последняя карточка запрашивается',
        () {
      fakeAsync((async) {
        final container = ProviderContainer(overrides: [
          apiClientProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);
        final scheduler = container.read(hoverPrefetchSchedulerProvider);
        final prefetched = <String>[];
        scheduler.schedule('a', (id) => prefetched.add(id));
        scheduler.schedule('b', (id) => prefetched.add(id));
        drain(async, time: const Duration(milliseconds: 200));
        expect(prefetched, ['b'],
            reason: 'один общий таймер: запросит только последняя');
      });
    });

    test('HoverPrefetchScheduler: во время скролла префетч гасится', () {
      fakeAsync((async) {
        final container = ProviderContainer(overrides: [
          apiClientProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);
        final scheduler = container.read(hoverPrefetchSchedulerProvider);
        final prefetched = <String>[];
        scheduler.setScrolling();
        scheduler.schedule('a', (id) => prefetched.add(id));
        drain(async, time: const Duration(milliseconds: 200));
        expect(prefetched, isEmpty,
            reason: 'скролл пролетает мимо, намерения нет');

        // +150 мс тишины — намерение снова принимается:
        scheduler.schedule('a', (id) => prefetched.add(id));
        drain(async, time: const Duration(milliseconds: 200));
        expect(prefetched, ['a']);
      });
    });
  });

  group('externalDetailPrefetch', () {
    test('loadExternalDetails: null → rejection (не залипает в кэше)',
        () async {
      var calls = 0;
      adapter = StubAdapter((options) {
        if (options.path == '/api/external/details') {
          calls += 1;
          return jsonBody(null, 404);
        }
        return jsonBody(null);
      });
      final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      dio.httpClientAdapter = adapter;
      api = TsundokuApi(dio);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      // Обычный async-контекст (не fakeAsync): expectLater корректен.
      await expectLater(
        loadExternalDetailsCore(container.read(externalDetailsCacheProvider),
            api, 'anime', ext('x1', 'Frieren')),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
      await expectLater(
        loadExternalDetailsCore(container.read(externalDetailsCacheProvider),
            api, 'anime', ext('x1', 'Frieren')),
        throwsA(isA<StateError>()),
      );
      expect(calls, 2);
    });

    test('loadExternalDetails: успех кэшируется по ключу type:source:id',
        () async {
      var calls = 0;
      adapter = StubAdapter((options) {
        if (options.path == '/api/external/details') {
          calls += 1;
          expect(options.queryParameters['type'], 'anime');
          expect(options.queryParameters['id'], 'x1');
          expect(options.queryParameters['source'], 'AniList');
          return jsonBody({
            'externalId': 'x1', 'externalSource': 'AniList',
            'title': 'Frieren', 'originalTitle': null, 'romajiTitle': null,
            'coverUrl': null, 'description': null, 'trailerVideoId': null,
            'releaseYear': null, 'releaseDate': null, 'endDate': null,
            'releaseStatus': null, 'format': null, 'runtimeMinutes': null,
            'type': 'anime', 'author': null, 'studio': null, 'isbn': null,
            'covers': null, 'totalCount': null, 'chapters': null,
            'volumes': null, 'mangaFormat': null, 'countryOfOrigin': null,
            'platform': null, 'rating': null, 'ratingVotes': null,
            'ratings': null, 'episodes': null, 'genres': null, 'tags': null,
            'synonyms': null,
          });
        }
        return jsonBody(null);
      });
      final dio2 = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
      dio2.httpClientAdapter = adapter;
      api = TsundokuApi(dio2);
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      final first = await loadExternalDetailsCore(
          container.read(externalDetailsCacheProvider), api, 'anime', ext('x1', 'Frieren'));
      expect(first.title, 'Frieren');
      final second = await loadExternalDetailsCore(
          container.read(externalDetailsCacheProvider), api, 'anime', ext('x1', 'Frieren'));
      expect(second.externalId, 'x1');
      expect(calls, 1, reason: 'тот же type:source:id — из кэша');
    });
  });

  group('drop_reason_prompt', () {
    test('open/close: target ставится и снимается, onClose вызывается',
        () async {
      final ctrl = container.read(dropPromptStateProvider.notifier);
      var closed = 0;
      ctrl.open(DropPromptTarget(id: 'm1', title: 'T', onClose: () => closed++));
      expect(container.read(dropPromptStateProvider)?.id, 'm1');
      ctrl.close();
      expect(container.read(dropPromptStateProvider), isNull);
      expect(closed, 1);
    });
  });
}
