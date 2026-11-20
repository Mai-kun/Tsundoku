import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tsundoku_flutter/shared/api/network_activity.dart';

/// Полный цикл: begin/end/reset + safety-таймер 15s (1-в-1 с Svelte-логикой).
void main() {
  ProviderContainer makeContainer() =>
      ProviderContainer(overrides: const []);
  late ProviderContainer container;

  setUp(() => container = makeContainer());
  tearDown(() => container.dispose());

  test('begin/end: счётчик растёт и убывает, isLoading derived', () {
    expect(container.read(networkActivityProvider), 0);
    expect(container.read(networkActivityLoadingProvider), isFalse);

    final ctrl = container.read(networkActivityProvider.notifier);
    ctrl.begin();
    expect(container.read(networkActivityProvider), 1);
    expect(container.read(networkActivityLoadingProvider), isTrue);

    ctrl.begin();
    expect(container.read(networkActivityProvider), 2);

    ctrl.end();
    expect(container.read(networkActivityProvider), 1);
    expect(container.read(networkActivityLoadingProvider), isTrue);

    ctrl.end();
    expect(container.read(networkActivityProvider), 0);
    expect(container.read(networkActivityLoadingProvider), isFalse);
  });

  test('end при 0 не уходит в минус (Math.max(0, ...))', () {
    final ctrl = container.read(networkActivityProvider.notifier);
    ctrl.end();
    ctrl.end();
    expect(container.read(networkActivityProvider), 0);
  });

  test('сafety-таймер 15s: сброс счётчика при зависшем запросе', () {
    fakeAsync((async) {
      final ctrl = container.read(networkActivityProvider.notifier);
      ctrl.begin();
      expect(container.read(networkActivityProvider), 1);

      // Меньше 15s — счётчик жив.
      async.elapse(const Duration(seconds: 14));
      expect(container.read(networkActivityProvider), 1);

      // На 15s safety-таймер делает reset() 1-в-1.
      async.elapse(const Duration(seconds: 1));
      expect(container.read(networkActivityProvider), 0);
      expect(container.read(networkActivityLoadingProvider), isFalse);
    });
  });

  test('end при 0 отменяет safety-таймер (не сбрасывает будущий begin)', () {
    fakeAsync((async) {
      final ctrl = container.read(networkActivityProvider.notifier);
      ctrl.begin();
      ctrl.end();
      expect(container.read(networkActivityProvider), 0);

      // Таймер от первого begin должен быть отменён: elapse 15s не ломает
      // последующий begin.
      async.elapse(const Duration(seconds: 15));
      ctrl.begin();
      expect(container.read(networkActivityProvider), 1);
      async.elapse(const Duration(seconds: 14));
      expect(container.read(networkActivityProvider), 1);
    });
  });

  test('reset() обнуляет счётчик и таймер немедленно', () {
    fakeAsync((async) {
      final ctrl = container.read(networkActivityProvider.notifier);
      ctrl.begin();
      ctrl.begin();
      expect(container.read(networkActivityProvider), 2);
      ctrl.reset();
      expect(container.read(networkActivityProvider), 0);
      // Таймер отменён: не сбросит будущий begin.
      async.elapse(const Duration(seconds: 15));
      ctrl.begin();
      expect(container.read(networkActivityProvider), 1);
    });
  });

  test('параллельные запросы: таймер перевооружается на каждый begin', () {
    fakeAsync((async) {
      final ctrl = container.read(networkActivityProvider.notifier);
      ctrl.begin();
      async.elapse(const Duration(seconds: 14));
      // Второй begin за 1s до срабатывания — перевооружает таймер на полные 15s.
      ctrl.begin();
      async.elapse(const Duration(seconds: 1));
      expect(container.read(networkActivityProvider), 2);
      ctrl.end();
      ctrl.end();
      expect(container.read(networkActivityProvider), 0);
    });
  });
}
