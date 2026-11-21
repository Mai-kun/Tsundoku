import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/relation_sources.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// Тесты `relationSources.ts`: whitelist relations-источников × включённые
/// пользователем (полный цикл через stub getSources).
void main() {
  Map<String, Object?> sourceJson(
    String id,
    String name,
    List<String> mediaTypes, {
    bool isEnabled = true,
  }) =>
      {
        'id': id,
        'name': name,
        'description': '',
        'mediaTypes': mediaTypes,
        'requiresApiKey': false,
        'optionalApiKey': false,
        'isConfigured': true,
        'hasKey': false,
        'maskedKey': null,
        'isEnabled': isEnabled,
        'isScraper': false,
        'isProxied': null,
      };

  MediaItem item(String type, {bool? isAnime}) => MediaItem.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'X',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'isAnime': isAnime,
      });

  Future<List<RelationSourceOption>> options(TsundokuApi api, MediaItem item) =>
      availableRelationSources(api, item);

  test('manga: whitelist-источники, суженные до включённых', () async {
    final adapter = StubAdapter((options) {
      expect(options.path, '/api/settings/sources');
      return jsonBody([
        sourceJson('anilist', 'AniList', ['anime', 'manga']),
        sourceJson('mangadex', 'MangaDex', ['manga']),
        sourceJson('shikimori', 'Shikimori', ['anime', 'manga'], isEnabled: false),
        sourceJson('openlibrary', 'OpenLibrary', ['book']),
        sourceJson('sociallib', 'SocialLib', ['manga']),
      ]);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);

    final result = await options(api, item('manga'));
    expect(result.map((r) => r.id), ['anilist', 'mangadex']);
  });

  test('isAnime-тайтл (tvshow + isAnime) → anime-бакет', () async {
    final adapter = StubAdapter((options) {
      return jsonBody([
        sourceJson('tmdb', 'TMDB', ['movie', 'tvshow']),
        sourceJson('anilist', 'AniList', ['anime', 'manga']),
      ]);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);

    final result = await options(api, item('tvshow', isAnime: true));
    expect(result.map((r) => r.id), ['anilist']);
  });

  test('book → whitelist kitsu/shikimori (не openlibrary)', () async {
    final adapter = StubAdapter((options) {
      return jsonBody([
        sourceJson('openlibrary', 'OpenLibrary', ['book']),
        sourceJson('kitsu', 'Kitsu', ['anime', 'manga', 'book']),
        sourceJson('shikimori', 'Shikimori', ['anime', 'manga']),
      ]);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);

    // book в whitelist → kitsu/shikimori; openlibrary не relations-capable.
    final book = await options(api, item('book'));
    expect(book.map((r) => r.id), ['kitsu', 'shikimori']);
  });

  test('ошибка getSources → [] (не роняет вызывающий flow)', () async {
    final adapter = StubAdapter((options) {
      return jsonBody({'detail': 'boom'}, 500);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);

    final result = await options(api, item('manga'));
    expect(result, isEmpty);
  });

  test('sourcesCachePromise: второй вызов идёт из кэша (1 запрос)', () async {
    var calls = 0;
    final adapter = StubAdapter((options) {
      calls += 1;
      return jsonBody([sourceJson('anilist', 'AniList', ['anime'])]);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);

    await options(api, item('tvshow', isAnime: true)); // бакет anime
    await options(api, item('manga'));
    expect(calls, 1); // sourcesCachePromise дедуплицирует
  });
}
