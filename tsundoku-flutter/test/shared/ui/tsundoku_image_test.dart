import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_image.dart';

class _TestBaseUrl extends ApiBaseUrlController {
  @override
  String build() => 'http://127.0.0.1:5000';
}

void main() {
  group('resolveTsundokuImageUrl', () {
    const baseUrl = 'http://127.0.0.1:5000';

    test('null or empty url returns empty string', () {
      expect(resolveTsundokuImageUrl(null, baseUrl), '');
      expect(resolveTsundokuImageUrl('', baseUrl), '');
      expect(resolveTsundokuImageUrl('   ', baseUrl), '');
    });

    test('relative /media-assets path is prefixed with baseUrl', () {
      final resolved = resolveTsundokuImageUrl('/media-assets/item1/cover/thumb.webp', baseUrl);
      expect(resolved, 'http://127.0.0.1:5000/media-assets/item1/cover/thumb.webp');
    });

    test('relative /api path is prefixed with baseUrl', () {
      final resolved = resolveTsundokuImageUrl('/api/external/image-proxy?url=https%3A%2F%2Fexample.com%2Fpic.jpg', baseUrl);
      expect(resolved, 'http://127.0.0.1:5000/api/external/image-proxy?url=https%3A%2F%2Fexample.com%2Fpic.jpg');
    });

    test('external https URL is wrapped via image-proxy and prefixed with baseUrl', () {
      const rawUrl = 'https://cdn.myanimelist.net/images/anime/13/11467.jpg';
      final resolved = resolveTsundokuImageUrl(rawUrl, baseUrl);
      expect(
        resolved,
        'http://127.0.0.1:5000/api/external/image-proxy?url=https%3A%2F%2Fcdn.myanimelist.net%2Fimages%2Fanime%2F13%2F11467.jpg',
      );
    });

    test('external http URL is wrapped via image-proxy and prefixed with baseUrl', () {
      const rawUrl = 'http://image.tmdb.org/t/p/w500/poster.jpg';
      final resolved = resolveTsundokuImageUrl(rawUrl, baseUrl);
      expect(
        resolved,
        'http://127.0.0.1:5000/api/external/image-proxy?url=http%3A%2F%2Fimage.tmdb.org%2Ft%2Fp%2Fw500%2Fposter.jpg',
      );
    });

    test('external URL with forceRefresh=true appends &forceRefresh=true', () {
      const rawUrl = 'https://cdn.example.com/image.png';
      final resolved = resolveTsundokuImageUrl(rawUrl, baseUrl, forceRefresh: true);
      expect(
        resolved,
        'http://127.0.0.1:5000/api/external/image-proxy?url=https%3A%2F%2Fcdn.example.com%2Fimage.png&forceRefresh=true',
      );
    });

    test('baseUrl with trailing slash is handled cleanly without double slashes', () {
      const slashBase = 'http://127.0.0.1:5000/';
      final resolved = resolveTsundokuImageUrl('/media-assets/item1/original.webp', slashBase);
      expect(resolved, 'http://127.0.0.1:5000/media-assets/item1/original.webp');
    });

    test('already resolved baseUrl URL is not double-wrapped', () {
      const alreadyResolved = 'http://127.0.0.1:5000/media-assets/item1/thumb.webp';
      expect(resolveTsundokuImageUrl(alreadyResolved, baseUrl), alreadyResolved);

      const alreadyProxied = 'http://127.0.0.1:5000/api/external/image-proxy?url=https%3A%2F%2Fexample.com';
      expect(resolveTsundokuImageUrl(alreadyProxied, baseUrl), alreadyProxied);
    });
  });

  group('TsundokuImage Widget', () {
    testWidgets('renders placeholder when src is null or empty', (tester) async {
      final container = ProviderContainer(overrides: [
        apiBaseUrlProvider.overrideWith(_TestBaseUrl.new),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: TsundokuImage(
              src: null,
              placeholder: KeyedSubtree(
                key: Key('custom-placeholder'),
                child: SizedBox(),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('custom-placeholder')), findsOneWidget);
    });

    testWidgets('renders errorBuilder when empty URL and errorBuilder provided', (tester) async {
      final container = ProviderContainer(overrides: [
        apiBaseUrlProvider.overrideWith(_TestBaseUrl.new),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: TsundokuImage(
              src: '',
              errorBuilder: (_, _, _) => const Text('Failed to load'),
            ),
          ),
        ),
      );

      expect(find.text('Failed to load'), findsOneWidget);
    });

    testWidgets('applies explicit cacheWidth unless fullSize is true', (tester) async {
      final container = ProviderContainer(overrides: [
        apiBaseUrlProvider.overrideWith(_TestBaseUrl.new),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Column(
              children: [
                TsundokuImage(
                  src: '/media-assets/item1/cover.webp',
                  cacheWidth: 480,
                ),
                TsundokuImage(
                  src: '/media-assets/item2/cover.webp',
                  cacheWidth: 480,
                  fullSize: true,
                ),
              ],
            ),
          ),
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(2));
      expect(images[0].image, isA<ResizeImage>());
      expect((images[0].image as ResizeImage).width, 480);
      expect(images[1].image, isA<NetworkImage>());
    });
  });
}
