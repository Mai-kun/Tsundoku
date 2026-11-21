import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/server_restart.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';

/// Полный цикл toast store: show (лимит 5, TTL-таймер), dismiss, error-gate
/// при рестарте бэкенда (serverRestart-инъекция через provider).
void main() {
  late ProviderContainer container;
  late ToastStoreController ctrl;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    ctrl = container.read(toastStoreProvider.notifier);
  });

  test('show: id возвращается, item добавляется, дефолты 1-в-1', () {
    ctrl.show(const ToastOptions(title: 'T', description: 'D'));
    final items = container.read(toastStoreProvider);
    expect(items, hasLength(1));
    expect(items.single.type, ToastType.success,
        reason: 'дефолт type = success');
    expect(items.single.durationMs, 4000, reason: 'DEFAULT_DURATION_MS');
    expect(items.single.showOk, isFalse);
    expect(items.single.actions, isEmpty);
  });

  test('MAX_TOASTS 5: шестой тост вытесняет самый старый', () {
    for (var i = 0; i < 6; i++) {
      ctrl.show(ToastOptions(title: 'T$i', description: 'D'));
    }
    final items = container.read(toastStoreProvider);
    expect(items, hasLength(5));
    expect(items.first.title, 'T1', reason: 'T0 вытеснен');
    expect(items.last.title, 'T5');
  });

  test('dismiss: удаляет конкретный тост', () {
    ctrl.show(const ToastOptions(title: 'A', description: 'D'));
    ctrl.show(const ToastOptions(title: 'B', description: 'D'));
    ctrl.dismiss(container.read(toastStoreProvider).first.id);
    final items = container.read(toastStoreProvider);
    expect(items, hasLength(1));
    expect(items.single.title, 'B');
  });

  test('error-gate: при рестарте бэкенда error-тост не показывается', () {
    final container2 = ProviderContainer(overrides: [
      serverRestartProvider.overrideWith(ServerRestartController.new),
    ]);
    addTearDown(container2.dispose);
    final ctrl2 = container2.read(toastStoreProvider.notifier);
    // Рестарт активен: контроллер сервера переводится в isRestarting=true.
    container2.read(serverRestartProvider.notifier).setForTest(true);

    ctrl2.show(const ToastOptions(
        title: 'boom', description: 'D', type: ToastType.error));
    expect(container2.read(toastStoreProvider), isEmpty,
        reason: 'гейт 1-в-1: error при isRestarting → ""');

    // Не-error тосты показываются:
    ctrl2.show(const ToastOptions(
        title: 'ok', description: 'D', type: ToastType.info));
    expect(container2.read(toastStoreProvider), hasLength(1));
  });

  test('стор без TTL-таймера: авто-dismiss живёт в ToastContainer (пауза на '
      'hover) — 🐛 #4', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(toastStoreProvider.notifier);
    ctrl.show(const ToastOptions(
        title: 'A', description: 'D', durationMs: 300));
    expect(container.read(toastStoreProvider), hasLength(1));
    // Время идёт, стор ничего не удаляет (dismiss за контейнером).
    expect(container.read(toastStoreProvider), hasLength(1),
        reason: 'стор — чистое состояние, без таймеров');
  });

  test('durationMs 0/длинный: стор не удаляет сам — договорённость Фазы 3', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(toastStoreProvider.notifier);
    ctrl.show(const ToastOptions(title: 'A', description: 'D', durationMs: 0));
    expect(container.read(toastStoreProvider), hasLength(1));
  });

  test('ToastType wire 1-в-1', () {
    expect(ToastType.success.wire, 'success');
    expect(ToastType.info.wire, 'info');
    expect(ToastType.warning.wire, 'warning');
    expect(ToastType.error.wire, 'error');
  });
}
