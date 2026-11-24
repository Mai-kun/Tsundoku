import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_image.dart';

void main() {
  const baseUrl = 'http://127.0.0.1:5000';
  final dio = Dio(BaseOptions(baseUrl: baseUrl));

  test('Live Server: Search Naruto, resolve 5 covers via proxy, and verify 0 HandshakeException', () async {
    // Check if live server is reachable
    try {
      final ping = await dio.get('/api/media');
      if (ping.statusCode != 200) return;
    } catch (_) {
      // Server not running, skip test
      return;
    }

    // 1. Search Naruto (type=anime)
    final searchRes = await dio.get('/api/external/search', queryParameters: {
      'type': 'anime',
      'query': 'Naruto',
    });
    expect(searchRes.statusCode, 200);
    final results = (searchRes.data as List<dynamic>).take(5).toList();
    expect(results.length, 5);

    // 2. Resolve every cover and fetch it
    for (final r in results) {
      final rawCoverUrl = r['coverUrl'] as String?;
      expect(rawCoverUrl, isNotNull);
      expect(rawCoverUrl, startsWith('http'));

      final resolved = resolveTsundokuImageUrl(rawCoverUrl, baseUrl);
      expect(resolved, contains('/api/external/image-proxy?url='));

      final imgRes = await dio.get(
        resolved,
        options: Options(responseType: ResponseType.bytes),
      );
      expect(imgRes.statusCode, 200);
      final contentType = imgRes.headers.value('content-type') ?? '';
      expect(contentType.startsWith('image/'), isTrue);
      expect((imgRes.data as List<int>).length, greaterThan(1000));
    }

    // 3. External details for Naruto
    final detailsRes = await dio.get('/api/external/details', queryParameters: {
      'type': 'anime',
      'id': '20',
      'title': 'Naruto',
    });
    expect(detailsRes.statusCode, 200);
    final detailCover = detailsRes.data['coverUrl'] as String?;
    expect(detailCover, isNotNull);

    final resolvedDetail = resolveTsundokuImageUrl(detailCover, baseUrl);
    final detailImgRes = await dio.get(
      resolvedDetail,
      options: Options(responseType: ResponseType.bytes),
    );
    expect(detailImgRes.statusCode, 200);
    expect((detailImgRes.data as List<int>).length, greaterThan(1000));

    // 4. Media in library (/media-assets/... relative cover)
    final mediaRes = await dio.get('/api/media');
    expect(mediaRes.statusCode, 200);
    final mediaList = mediaRes.data as List<dynamic>;
    if (mediaList.isNotEmpty) {
      final first = mediaList.first;
      final localCover = first['coverUrl'] as String?;
      if (localCover != null && localCover.isNotEmpty) {
        final resolvedLocal = resolveTsundokuImageUrl(localCover, baseUrl);
        expect(resolvedLocal, startsWith(baseUrl));

        final localImgRes = await dio.get(
          resolvedLocal,
          options: Options(responseType: ResponseType.bytes),
        );
        expect(localImgRes.statusCode, 200);
        expect((localImgRes.data as List<int>).length, greaterThan(1000));
      }
    }
  });
}
