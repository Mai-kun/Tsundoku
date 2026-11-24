/// 1:1 port of `mediatracker-ui/src/shared/ui/holdToDelete.svelte.ts`.
///
/// Hold-to-confirm controller: computes `progress` (0..1) on a periodic tick
/// while the pointer is held; the caller animates scaleX(progress). An early
/// release rolls the fill back and never completes; a tap shorter than
/// `shortPressMs` shows the hint instead. `dispose()` clears tick/timers.
///
/// rAF → [Timer.periodic] с шагом кадра (16ms ≈ 60fps) — переносимо на все
/// платформы (решение #13).
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';


class HoldToDeleteOptions {
  /// Hold duration in ms (default 1000).
  final int? durationMs;

  /// Releases shorter than this count as a tap and trigger `onShortPress`
  /// (default 300).
  final int? shortPressMs;

  /// How long the hint stays visible after a short tap (default 1500).
  final int? hintMs;

  /// Fill rollback duration after an early release (default 220).
  final int? rollbackMs;

  /// Fired once the hold runs to completion.
  final void Function() onComplete;

  /// Fired when the press ends before `shortPressMs` — the "hold longer" hint
  /// moment.
  final void Function()? onShortPress;

  /// Optional gate: when false, press/release events are ignored (e.g. while
  /// busy).
  final bool Function()? isEnabled;

  const HoldToDeleteOptions({
    this.durationMs,
    this.shortPressMs,
    this.hintMs,
    this.rollbackMs,
    required this.onComplete,
    this.onShortPress,
    this.isEnabled,
  });
}

class _HoldNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class HoldToDeleteController {
  /// Fill ratio 0..1; caller binds scaleX(progress) with origin-left.
  double progress = 0;
  bool holding = false;
  bool hintVisible = false;

  final HoldToDeleteOptions options;
  final _HoldNotifier _notifier = _HoldNotifier();
  Timer? _raf;
  int _startedAt = 0;
  int _lastFrameAt = 0;
  Timer? _hintTimer;

  /// Emits whenever [progress], [holding], or [hintVisible] changes.
  Listenable get changes => _notifier;

  static const int _defaultDurationMs = 1000;
  static const int _defaultShortPressMs = 300;
  static const int _defaultHintMs = 1500;
  static const int _defaultRollbackMs = 220;
  static const Duration _frameStep = Duration(milliseconds: 16);

  HoldToDeleteController(this.options);

  void press() {
    if (options.isEnabled?.call() == false) return;
    if (holding) return;
    _clearHint(notify: false);
    holding = true;
    _startedAt = clock.now().millisecondsSinceEpoch;
    _lastFrameAt = _startedAt;
    _raf?.cancel();
    _raf = Timer.periodic(_frameStep, (_) => _frame());
    _notifier.notify();
  }

  void release() {
    if (!holding) return;
    holding = false;
    final heldMs = clock.now().millisecondsSinceEpoch - _startedAt;
    if (heldMs < (options.shortPressMs ?? _defaultShortPressMs)) {
      _startRollback();
      _showHint();
      options.onShortPress?.call();
      _notifier.notify();
      return;
    }
    _startRollback();
    _notifier.notify();
  }

  /// Completes immediately — the keyboard path (Enter/Space) skips the hold.
  void completeNow() {
    if (options.isEnabled?.call() == false) return;
    _stop();
    options.onComplete();
  }

  void dispose() {
    _stop();
    _clearHint();
  }

  void _frame() {
    final now = clock.now().millisecondsSinceEpoch;
    final dt = now - _lastFrameAt;
    _lastFrameAt = now;
    if (holding) {
      progress = _min(1, (now - _startedAt) / _duration());
      if (progress >= 1) {
        _stop();
        options.onComplete();
        return;
      }
      _notifier.notify();
    } else {
      progress = _max(0, progress - dt / _rollback());
      _notifier.notify();
      if (progress <= 0) {
        _raf?.cancel();
        return;
      }
    }
  }

  void _startRollback() {
    _raf?.cancel();
    _lastFrameAt = clock.now().millisecondsSinceEpoch;
    _raf = Timer.periodic(_frameStep, (_) => _frame());
  }

  void _stop() {
    final changed = holding || progress != 0;
    holding = false;
    progress = 0;
    _raf?.cancel();
    if (changed) _notifier.notify();
  }

  void _showHint() {
    _clearHint(notify: false);
    hintVisible = true;
    _hintTimer = Timer(Duration(milliseconds: options.hintMs ?? _defaultHintMs),
        () {
      hintVisible = false;
      _hintTimer = null;
      _notifier.notify();
    });
  }

  void _clearHint({bool notify = true}) {
    if (_hintTimer != null) {
      _hintTimer!.cancel();
      _hintTimer = null;
    }
    final changed = hintVisible;
    hintVisible = false;
    if (changed && notify) _notifier.notify();
  }

  double _duration() =>
      (options.durationMs ?? _defaultDurationMs).toDouble();

  double _rollback() =>
      (options.rollbackMs ?? _defaultRollbackMs).toDouble();
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

/// `createHoldToDelete(options)` — тот же API именованным конструктором.
HoldToDeleteController createHoldToDelete(HoldToDeleteOptions options) =>
    HoldToDeleteController(options);
