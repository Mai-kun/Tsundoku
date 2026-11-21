import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/utils/viewport.dart';

void main() {
  test('дефолт 1280 (аналог window.innerWidth до первого resize)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(viewportProvider), defaultViewportWidth);
    expect(container.read(viewportProvider), 1280);
  });

  test('update: живой ресайз обновляет ширину', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(viewportProvider.notifier);
    ctrl.update(1440);
    expect(container.read(viewportProvider), 1440);
    ctrl.update(900);
    expect(container.read(viewportProvider), 900);
  });

  test('update тем же значением не перерисовывает', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var rebuilds = 0;
    container.listen(viewportProvider, (prev, next) => rebuilds++);
    final ctrl = container.read(viewportProvider.notifier);
    ctrl.update(1440);
    ctrl.update(1440);
    expect(rebuilds, 1,
        reason: 'одно изменение; повторный update тем же значением — нет');
  });
}
