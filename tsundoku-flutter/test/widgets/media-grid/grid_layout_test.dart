import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/widgets/media-grid/grid_layout.dart';

/// Тесты `gridLayout.svelte.ts`: глобальный счётчик версий — bump растёт,
/// watch-подписчики перестраиваются.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('стартовая версия 0', () {
    expect(container.read(gridLayoutVersionProvider), 0);
  });

  test('bumpGridLayout инкрементирует глобальную версию', () {
    final ref = container;
    bumpGridLayout(ref);
    bumpGridLayout(ref);
    expect(container.read(gridLayoutVersionProvider), 2);
  });

  test('watch-подписчики уведомляются при bump (аналог эффект-трекинга)',
      () {
    final versions = <int>[];
    final sub = container.listen(
      gridLayoutVersionProvider,
      (_, next) => versions.add(next),
    );
    addTearDown(sub.close);
    bumpGridLayout(container);
    expect(versions, [1]);
  });
}
