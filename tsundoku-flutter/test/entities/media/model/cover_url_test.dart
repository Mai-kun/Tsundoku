import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/cover_url.dart';

/// Прямой перенос vitest-кейсов `coverUrl.test.ts`.
void main() {
  test('resolves stored local thumb to full-size sibling', () {
    expect(fullSizeCoverUrl('/media-assets/2f1c0b3a/cover/thumb.webp'),
        '/media-assets/2f1c0b3a/cover/original.webp');
    expect(fullSizeCoverUrl('/media-assets/2f1c0b3a/covers/c123abc/thumb.webp'),
        '/media-assets/2f1c0b3a/covers/c123abc/original.webp');
  });

  test('preserves query string when swapping to original', () {
    expect(fullSizeCoverUrl('/media-assets/2f1c0b3a/cover/thumb.webp?v=3'),
        '/media-assets/2f1c0b3a/cover/original.webp?v=3');
    expect(
        fullSizeCoverUrl('/media-assets/2f1c0b3a/covers/c123abc/thumb.webp?v=3'),
        '/media-assets/2f1c0b3a/covers/c123abc/original.webp?v=3');
  });

  test('leaves external and legacy URLs untouched', () {
    expect(fullSizeCoverUrl('https://image.tmdb.org/t/p/original/abc.jpg'),
        'https://image.tmdb.org/t/p/original/abc.jpg');
    expect(fullSizeCoverUrl('/covers/legacy-row.webp'), '/covers/legacy-row.webp');
  });

  test('validates cover URLs correctly', () {
    expect(isValidCoverUrl('/media-assets/2f1c0b3a/cover/thumb.webp'), isTrue);
    expect(isValidCoverUrl(''), isTrue);
    expect(isValidCoverUrl('https://image.tmdb.org/t/p/w500/abc.jpg'), isTrue);
    expect(isValidCoverUrl('http://example.com/a.jpg'), isTrue);

    expect(isValidCoverUrl('not a url'), isFalse);
    expect(isValidCoverUrl('ftp://example.com/a.jpg'), isFalse);
  });

  test('proxiedExternalCoverUrl: локальные пути не проксируются', () {
    expect(proxiedExternalCoverUrl('/media-assets/a/cover/thumb.webp'),
        '/media-assets/a/cover/thumb.webp');
    expect(proxiedExternalCoverUrl('  '), '', reason: '1-в-1: возвращается trimmed');
  });

  test('proxiedExternalCoverUrl: внешние URL через image-proxy', () {
    final url = proxiedExternalCoverUrl('https://cdn.example/x.jpg');
    expect(url, startsWith('/api/external/image-proxy?url='));
    expect(url, contains(Uri.encodeComponent('https://cdn.example/x.jpg')));
    expect(url.contains('forceRefresh'), isFalse);
  });

  test('proxiedExternalCoverUrl: forceRefresh добавляет параметр', () {
    final url = proxiedExternalCoverUrl('https://cdn.example/x.jpg',
        forceRefresh: true);
    expect(url, contains('&forceRefresh=true'));
  });
}
