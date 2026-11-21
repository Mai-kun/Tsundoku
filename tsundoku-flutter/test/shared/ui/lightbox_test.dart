import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/ui/lightbox.dart';

/// Полный цикл lightbox-стора: open (url guard)/close.
void main() {
  late ProviderContainer container;
  late LightboxController ctrl;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    ctrl = container.read(lightboxProvider.notifier);
  });

  test('openLightbox: url + caption', () {
    ctrl.openLightbox('https://cdn.example/full.webp', 'Норагами');
    final state = container.read(lightboxProvider);
    expect(state.url, 'https://cdn.example/full.webp');
    expect(state.caption, 'Норагами');
    expect(state.isOpen, isTrue);
  });

  test('openLightbox без caption → caption null', () {
    ctrl.openLightbox('https://cdn.example/x.jpg');
    expect(container.read(lightboxProvider).caption, isNull);
  });

  test('openLightbox: null/пустой url игнорируется (guard 1-в-1)', () {
    ctrl.openLightbox(null);
    expect(container.read(lightboxProvider).url, isNull);
    ctrl.openLightbox('');
    expect(container.read(lightboxProvider).url, isNull);
  });

  test('closeLightbox: url/caption сбрасываются', () {
    ctrl.openLightbox('https://cdn.example/full.webp', 'C');
    ctrl.closeLightbox();
    expect(container.read(lightboxProvider).url, isNull);
    expect(container.read(lightboxProvider).isOpen, isFalse);
  });
}
