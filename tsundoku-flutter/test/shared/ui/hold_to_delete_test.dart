import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tsundoku_flutter/shared/ui/hold_to_delete.dart';

/// Прямой перенос vitest-семантики `holdToDelete.svelte.ts`: hold → progress
/// 0..1 → complete; короткий тап → rollback + hint; isEnabled-гейт.
void main() {
  test('press/release: полный холд завершается onComplete', () {
    fakeAsync((async) {
      var completed = 0;
      final ctrl = HoldToDeleteController(
          HoldToDeleteOptions(
              durationMs: 1000, shortPressMs: 300, onComplete: () => completed++));

      ctrl.press();
      expect(ctrl.holding, isTrue);
      async.elapse(const Duration(milliseconds: 1100));
      expect(completed, 1);
      expect(ctrl.holding, isFalse);
      expect(ctrl.progress, 0, reason: 'после завершения progress сброшен');
    });
  });

  test('короткий тап: rollback + hint + onShortPress, без completion', () {
    fakeAsync((async) {
      var completed = 0;
      var shortPress = 0;
      final ctrl = HoldToDeleteController(HoldToDeleteOptions(
          durationMs: 1000,
          shortPressMs: 300,
          hintMs: 1500,
          onComplete: () => completed++,
          onShortPress: () => shortPress++));

      ctrl.press();
      async.elapse(const Duration(milliseconds: 150)); // < 300ms
      ctrl.release();
      expect(completed, 0);
      expect(shortPress, 1);
      expect(ctrl.hintVisible, isTrue);

      // Hint живёт 1.5s:
      async.elapse(const Duration(milliseconds: 1000));
      expect(ctrl.hintVisible, isTrue);
      async.elapse(const Duration(milliseconds: 600));
      expect(ctrl.hintVisible, isFalse);
    });
  });

  test('rollback после раннего release: progress → 0', () {
    fakeAsync((async) {
      final ctrl = HoldToDeleteController(HoldToDeleteOptions(
          durationMs: 1000,
          shortPressMs: 300,
          rollbackMs: 220,
          onComplete: () {}));
      ctrl.press();
      async.elapse(const Duration(milliseconds: 200));
      ctrl.release();
      // progress > 0 сразу после release:
      expect(ctrl.progress > 0, isTrue);
      async.elapse(const Duration(milliseconds: 400));
      expect(ctrl.progress, 0, reason: 'rollbackMs 220ms — fill спал до нуля');
    });
  });

  test('isEnabled=false: press/release игнорируются', () {
    fakeAsync((async) {
      var completed = 0;
      final ctrl = HoldToDeleteController(HoldToDeleteOptions(
          isEnabled: () => false,
          durationMs: 1000,
          onComplete: () => completed++));
      ctrl.press();
      async.elapse(const Duration(milliseconds: 1200));
      expect(completed, 0);
      expect(ctrl.holding, isFalse);
    });
  });

  test('completeNow: мгновенное завершение (клавиатурный путь)', () {
    var completed = 0;
    final c = HoldToDeleteController(
        HoldToDeleteOptions(durationMs: 1000, onComplete: () => completed++));
    c.press();
    c.completeNow();
    expect(completed, 1);
    expect(c.progress, 0);
  });

  test('dispose: снимает rAF и hint (не завершает после dispose)', () {
    fakeAsync((async) {
      var completed = 0;
      final ctrl = HoldToDeleteController(
          HoldToDeleteOptions(durationMs: 1000, onComplete: () => completed++));
      ctrl.press();
      ctrl.dispose();
      async.elapse(const Duration(milliseconds: 1500));
      expect(completed, 0, reason: 'после dispose холд не завершается');
    });
  });

  test('дефолты 1-в-1 (1000/300/1500/220)', () {
    fakeAsync((async) {
      var completed = 0;
      final c = HoldToDeleteController(
          HoldToDeleteOptions(onComplete: () => completed++));
      c.press();
      async.elapse(const Duration(milliseconds: 1100));
      expect(completed, 1, reason: 'default durationMs = 1000');
    });
  });
}
