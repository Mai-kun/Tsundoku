import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// Stub HttpClientAdapter: маршрутизация (method, path) → ResponseBody.
/// Позволяет проверять method/path/payload каждого вызова (полный цикл).
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

ResponseBody jsonBody(Object? json,
        {int status = 200, Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...?headers,
      },
    );

ResponseBody bytesBody(List<int> bytes, {int status = 200}) =>
    ResponseBody.fromBytes(bytes, status);

void main() {
  late StubAdapter adapter;
  late TsundokuApi api;
  var started = 0;
  var ended = 0;

  TsundokuApi makeApi(
      ResponseBody Function(RequestOptions options) handler) {
    adapter = StubAdapter(handler);
    final dio = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:5150',
      connectTimeout: TsundokuApi.requestTimeout,
      receiveTimeout: TsundokuApi.requestTimeout,
      sendTimeout: TsundokuApi.requestTimeout,
    ));
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    api.onRequestStart = () {
      started++;
    };
    api.onRequestEnd = () {
      ended++;
    };
    return api;
  }

  setUp(() {
    started = 0;
    ended = 0;
  });

  group('getMediaWithCount (X-Total-Count + query-построение)', () {
    test('полный цикл: payload → модели + header total', () async {
      api = makeApi((options) {
        expect(options.method, 'GET');
        expect(options.path, '/api/media');
        // Дефолты sortBy=createdAt/sortOrder=desc из исходника:
        expect(options.queryParameters['sortBy'], 'createdAt');
        expect(options.queryParameters['sortOrder'], 'desc');
        return jsonBody([
          {
            'id': 'm1', 'type': 'book', 'title': 'Дюна', 'status': 1,
            'createdAt': '2026-11-01T00:00:00Z', 'author': 'Герберт',
            'currentPage': 3, 'totalPages': 412,
          },
        ], headers: {'x-total-count': ['25']});
      });

      final page = await api.getMediaWithCount(
          const MediaFilters(type: MediaType.book, search: 'дюна'));
      expect(page.items.single.title, 'Дюна');
      expect(page.items.single.currentPage, 3);
      expect(page.totalCount, 25);
      // query фильтра тоже ушёл:
      expect(adapter.seen.single.queryParameters['type'], 'book');
      expect(adapter.seen.single.queryParameters['search'], 'дюна');
      // networkActivity begin/end парные:
      expect(started, 1);
      expect(ended, 1);
    });

    test('нет валидного X-Total-Count → totalCount = items.length', () async {
      api = makeApi((options) =>
          jsonBody([{'id': 'm1', 'type': 'game', 'title': 'Hades', 'status': 0, 'createdAt': '2026-11-01T00:00:00Z'}]));
      final page = await api.getMediaWithCount();
      expect(page.totalCount, 1);
    });

    test('getMedia() возвращает только items', () async {
      api = makeApi((options) => jsonBody(<Map<String, dynamic>>[]));
      final items = await api.getMedia();
      expect(items, isEmpty);
    });
  });

  group('ApiError / ProblemDetails / errorMessage', () {
    test('422 + errors → ApiError со validationErrors', () async {
      api = makeApi((options) => jsonBody({
            'detail': 'Validation failed',
            'errors': {
              'title': ['Title is required', 'Title is too long'],
              'score': ['Score out of range'],
            },
          }, status: 422));

      await expectLater(
        api.createMedia(const CreateGamePayload(
          platform: 'PC',
          hoursPlayed: null,
          title: '',
          status: MediaStatus.planned,
          altTitles: null, score: null, coverUrl: null, notes: null,
          description: null, trailerVideoId: null, franchiseId: null,
          franchiseName: null, franchiseOrder: null, externalId: null,
          externalSource: null, importSource: null, externalRating: null,
          externalRatingVotes: null, externalRatingsJson: null,
          releaseDate: null, endDate: null, releaseStatus: null,
          genres: null, tags: null, unlockedAchievements: null,
          userPlatform: null,
        )),
        throwsA(isA<ApiError>()
            .having((e) => e.status, 'status', 422)
            .having((e) => e.detail, 'detail', 'Validation failed')
            .having((e) => e.validationErrors['title'], 'title errors',
                ['Title is required', 'Title is too long'])),
      );
    });

    test('errorMessage: validation message → detail → i18n', () {
      final err = ApiError(422, detail: 'Validation failed', validationErrors: {
        'title': ['Title is required'],
      });
      expect(errorMessage(err, Locale.en), 'Title is required');

      final err2 = ApiError(500, detail: 'Server exploded');
      expect(errorMessage(err2, Locale.en), 'Server exploded');

      final err3 = ApiError(404);
      expect(errorMessage(err3, Locale.en), isNotEmpty);
      expect(errorMessage(err3, Locale.ru), isNotEmpty);

      // Не-ApiError → errors.unexpected (не пустая строка, для ru/en).
      expect(errorMessage(StateError('boom'), Locale.en),
          isNot(equals('boom')));
      expect(errorMessage(StateError('boom'), Locale.en), isNotEmpty);
    });

    test('ошибка валидации: не-объектный payload → пустая ProblemDetails',
        () async {
      api = makeApi((options) => jsonBody('not an object', status: 500));
      try {
        await api.getMediaItem('m1');
        fail('must throw');
      } on ApiError catch (e) {
        expect(e.status, 500);
        expect(e.detail, isEmpty);
        expect(e.validationErrors, isEmpty);
      }
      // При ошибке end() всё равно вызван (finally):
      expect(ended, 1);
    });
  });

  group('updateStatus / updateStatusWithDropInfo (решение #9)', () {
    test('чистый статус: payload {status} без drop-полей', () async {
      api = makeApi((options) => jsonBody(null));
      await api.updateStatus('m1', MediaStatus.dropped);
      final opts = adapter.seen.single;
      expect(opts.method, 'PUT');
      expect(opts.path, '/api/media/m1/status');
      expect(opts.data, {'status': 4});
    });

    test('статус с drop-полями: null сериализуется явно (1-в-1 TS-объект)',
        () async {
      api = makeApi((options) => jsonBody(null));
      await api.updateStatusWithDropInfo('m1', MediaStatus.dropped,
          dropReason: 'Не зашло', dropNotes: null);
      expect(adapter.seen.single.data, {
        'status': 4,
        'dropReason': 'Не зашло',
        'dropNotes': null,
      });
    });
  });

  group('setProgress / setSeasonProgress (payload-проверки)', () {
    test('setProgress PUT progress', () async {
      api = makeApi((options) => jsonBody(null));
      await api.setProgress('m1', 42);
      expect(adapter.seen.single.method, 'PUT');
      expect(adapter.seen.single.path, '/api/media/m1/progress');
      expect(adapter.seen.single.data, {'currentProgress': 42});
    });

    test('setSeasonProgress PUT /api/seasons/{id}/progress', () async {
      api = makeApi((options) => jsonBody(null));
      await api.setSeasonProgress('s1', 7);
      expect(adapter.seen.single.path, '/api/seasons/s1/progress');
      expect(adapter.seen.single.data, {'currentEpisode': 7});
    });
  });

  group('detectMangalibBrowserSession (404 → null)', () {
    test('200 → MangalibDetectResult + invalidateSourcesCache', () async {
      var sourcesCalls = 0;
      api = makeApi((options) {
        if (options.path == '/api/settings/sources') {
          sourcesCalls += 1;
          return jsonBody(<Map<String, dynamic>>[]);
        }
        if (options.path == '/api/settings/sources/mangalib/detect-token') {
          return jsonBody({
            'success': true, 'userId': 42, 'username': 'user',
            'source': 'zen-profile', 'message': null,
          });
        }
        return jsonBody(null, status: 404);
      });

      // Прогрев кэша sources.
      await api.getSources();
      expect(sourcesCalls, 1);
      await api.getSources();
      expect(sourcesCalls, 1, reason: 'sourcesCachePromise отдаёт кэш');

      final result = await api.detectMangalibBrowserSession();
      expect(result?.userId, 42);
      expect(result?.username, 'user');

      // detect инвалидирует кэш источников:
      await api.getSources();
      expect(sourcesCalls, 2);
    });

    test('404 → null без исключения', () async {
      api = makeApi((options) => jsonBody(null, status: 404));
      final result = await api.detectSimklBrowserSession();
      expect(result, isNull);
    });

    test('500 → ApiError (не null)', () async {
      api = makeApi(
          (options) => jsonBody({'detail': 'no browser'}, status: 500));
      await expectLater(
        api.detectMangalibBrowserSession(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 500)),
      );
    });
  });

  group('getSources: ошибка сбрасывает кэш', () {
    test('первый вызов упал → второй идёт в сеть заново', () async {
      var calls = 0;
      api = makeApi((options) {
        if (options.path == '/api/settings/sources') {
          calls += 1;
          return calls == 1
              ? jsonBody({'detail': 'server not ready'}, status: 503)
              : jsonBody(<Map<String, dynamic>>[]);
        }
        return jsonBody(null);
      });
      await expectLater(api.getSources(), throwsA(isA<ApiError>()));
      final sources = await api.getSources();
      expect(sources, isEmpty);
      expect(calls, 2);
    });
  });

  group('getExternalDetails (catch → null)', () {
    test('любая ошибка → null (1-в-1 .catch(() => null))', () async {
      api = makeApi((options) => jsonBody({'detail': 'miss'}, status: 404));
      final result =
          await api.getExternalDetails('manga', 'x1', 'Frieren');
      expect(result, isNull);
    });

    test('успех → ExternalMedia', () async {
      api = makeApi((options) {
        expect(options.queryParameters['type'], 'anime');
        expect(options.queryParameters['id'], 'x1');
        expect(options.queryParameters['title'], 'Frieren');
        return jsonBody({
          'externalId': 'x1', 'externalSource': 'AniList', 'title': 'Frieren',
          'originalTitle': null, 'romajiTitle': null, 'coverUrl': null,
          'description': null, 'trailerVideoId': null, 'releaseYear': null,
          'releaseDate': null, 'endDate': null, 'releaseStatus': null,
          'format': null, 'runtimeMinutes': null, 'type': 'anime',
          'author': null, 'studio': null, 'isbn': null, 'covers': null,
          'totalCount': null, 'chapters': null, 'volumes': null,
          'mangaFormat': null, 'countryOfOrigin': null, 'platform': null,
          'rating': null, 'ratingVotes': null, 'ratings': null,
          'episodes': null, 'genres': null, 'tags': null, 'synonyms': null,
        });
      });
      final result = await api.getExternalDetails('anime', 'x1', 'Frieren');
      expect(result?.externalId, 'x1');
    });
  });

  group('Бинарные ответы (Blob → Uint8List)', () {
    test('exportBackup возвращает байты', () async {
      api = makeApi((options) {
        expect(options.responseType, ResponseType.bytes);
        return bytesBody(utf8.encode('PK-backup'));
      });
      final bytes = await api.exportBackup();
      expect(utf8.decode(bytes), 'PK-backup');
    });

    test('exportCalendarIcs: 500 → ApiError', () async {
      api = makeApi((options) => bytesBody(utf8.encode('err'), status: 500));
      await expectLater(
        api.exportCalendarIcs(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 500)),
      );
    });
  });

  group('createList возвращает {id}', () {
    test('payload toJson + извлечение id', () async {
      api = makeApi((options) {
        expect(options.method, 'POST');
        expect(options.path, '/api/lists');
        expect(options.data['name'], '2026');
        return jsonBody({'id': 'list-9'});
      });
      const payload = CreateListPayload(
        name: '2026', description: null, icon: null, color: null,
        smartQueryJson: null,
      );
      final id = await api.createList(payload);
      expect(id, 'list-9');
    });
  });

  group('Desktop HTTP Transport (baseUrl propagation)', () {
    test('_opts propagates baseUrl to RequestOptions so uri has full host', () async {
      api = makeApi((options) => jsonBody([]));
      await api.getMedia();
      final seenOptions = adapter.seen.single;
      expect(seenOptions.baseUrl, 'http://127.0.0.1:5150');
      expect(seenOptions.uri.toString(), startsWith('http://127.0.0.1:5150/api/media'));
    });
  });

  group('Таймаут 15s (аналог AbortSignal.timeout(15000))', () {
    test('requestTimeout = 15000ms и выставлен на каждый запрос', () async {
      api = makeApi((options) => jsonBody(null));
      await api.shutdownApp();
      expect(TsundokuApi.requestTimeout, const Duration(milliseconds: 15000));
      expect(adapter.seen.single.sendTimeout,
          const Duration(milliseconds: 15000));
      expect(adapter.seen.single.receiveTimeout,
          const Duration(milliseconds: 15000));
    });
  });

  group('Startup connection retry (cold-start Kestrel race)', () {
    test('retries connectionError up to 10 times and succeeds once server binds port', () async {
      var attempts = 0;
      adapter = StubAdapter((options) {
        attempts++;
        if (attempts < 4) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'SocketException: Connection refused',
          );
        }
        return jsonBody(<Map<String, dynamic>>[]);
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:5150'))
        ..httpClientAdapter = adapter;
      api = TsundokuApi(dio, connectionRetryDelay: const Duration(milliseconds: 1));
      api.onRequestStart = () => started++;
      api.onRequestEnd = () => ended++;

      final list = await api.getMedia();
      expect(list, isEmpty);
      expect(attempts, 4);
      expect(started, 1);
      expect(ended, 1);
    });

    test('throws DioException after 10 connection retries are exhausted', () async {
      var attempts = 0;
      adapter = StubAdapter((options) {
        attempts++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'SocketException: Connection refused',
        );
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:5150'))
        ..httpClientAdapter = adapter;
      api = TsundokuApi(dio, connectionRetryDelay: const Duration(milliseconds: 1));
      api.onRequestStart = () => started++;
      api.onRequestEnd = () => ended++;

      await expectLater(api.getStorageSettings(), throwsA(isA<DioException>()));
      expect(attempts, TsundokuApi.maxConnectionRetries + 1);
      expect(started, 1);
      expect(ended, 1);
    });
  });
}
