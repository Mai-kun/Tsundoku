import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Базовый множитель шага колеса мыши (убирает «тяжесть» мелкого шага GTK/Linux).
const double kWheelStepMultiplier = 1.75;

/// Максимальный дополнительный множитель ускорения при быстром вращении колеса подряд.
const double kFastSpinMaxBoost = 2.1;

/// Окно детекции быстрого последовательного вращения колеса в мс.
const int kFastSpinWindowMs = 85;

/// Длительность анимации доводки скролла в мс (кривая Chromium EaseOutCubic).
const int kScrollDurationMs = 155;

/// Глобальный [ScrollBehavior] приложения.
///
/// Оборачивает вертикальные [Scrollable] в лёгкий маркер [_ScrollableAnchor],
/// чтобы корневой [TsundokuSmoothWheelInterceptor] надёжно находил любой
/// вертикальный `ScrollPosition` (включая `SingleChildScrollView`) даже в
/// release-сборках без `debugCreator`.
class TsundokuSmoothScrollBehavior extends MaterialScrollBehavior {
  const TsundokuSmoothScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final Widget wrapped = axisDirectionToAxis(details.direction) == Axis.vertical
        ? _ScrollableAnchor(
            scrollableContext: context,
            details: details,
            child: child,
          )
        : child;
    return super.buildOverscrollIndicator(context, wrapped, details);
  }
}

/// Корневой перехватчик колёсика мыши с плавной 144 FPS интерполяцией.
///
/// Оборачивает всё приложение в `MaterialApp.builder`. В своём
/// [RenderProxyBox.hitTest] сначала добавляет себя в `BoxHitTestResult`
/// (оказываясь на индексе 0 — раньше любого `Scrollable._receivedPointerSignal`),
/// а затем вызывает `hitTestChildren`. Благодаря этому наш обработчик всегда
/// выигрывает `GestureBinding.instance.pointerSignalResolver.register` у
/// стандартного `Scrollable` и не допускает мгновенного скачка на весь
/// `scrollDelta.dy`.
///
/// Тачпады (`PointerDeviceKind.trackpad`), `Ctrl + Wheel`, горизонтальные
/// списки и списки, уже достигшие края по направлению скролла, пропускаются
/// без перехвата.
class TsundokuSmoothWheelInterceptor extends SingleChildRenderObjectWidget {
  const TsundokuSmoothWheelInterceptor({
    super.key,
    required super.child,
  });

  /// Удобный builder для передачи в `MaterialApp.builder`.
  static Widget builder(BuildContext context, Widget? child) {
    return TsundokuSmoothWheelInterceptor(
      child: child ?? const SizedBox.shrink(),
    );
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSmoothWheelInterceptor();
  }
}

class _ScrollableCandidate {
  final ScrollPosition position;
  final AxisDirection axisDirection;

  const _ScrollableCandidate({
    required this.position,
    required this.axisDirection,
  });
}

class _SmoothWheelHitTestEntry extends BoxHitTestEntry {
  List<_ScrollableCandidate> candidates = const <_ScrollableCandidate>[];

  _SmoothWheelHitTestEntry(super.target, super.localPosition);
}

class _GlideState {
  double startPixels;
  double currentPixels;
  double targetPixels;
  double animStartTimeMs;
  double? lastWrittenPixels;

  _GlideState({
    required this.startPixels,
    required this.currentPixels,
    required this.targetPixels,
    required this.animStartTimeMs,
    this.lastWrittenPixels,
  });
}

class _RenderSmoothWheelInterceptor extends RenderProxyBox {
  late final Ticker _ticker = Ticker(_onTick);
  late final Stopwatch _clock =
      GestureBinding.instance.samplingClock.stopwatch()..start();
  final Map<ScrollPosition, _GlideState> _activeGlides =
      <ScrollPosition, _GlideState>{};

  ScrollPosition? _lastWheelPosition;
  double? _lastWheelTimeMs;
  int _lastWheelDirection = 0;
  double _spinBoost = 1.0;

  double get _nowMs => _clock.elapsedMicroseconds / 1000.0;

  static double _easeOutCubic(double t) {
    final double clamped = t.clamp(0.0, 1.0);
    return 1.0 - math.pow(1.0 - clamped, 3).toDouble();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _activeGlides.clear();
    _lastWheelPosition = null;
    _lastWheelTimeMs = null;
    _lastWheelDirection = 0;
    _spinBoost = 1.0;
    super.dispose();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    // Сначала добавляем себя (индекс 0 в result.path), затем обходим детей.
    final _SmoothWheelHitTestEntry entry =
        _SmoothWheelHitTestEntry(this, position);
    result.add(entry);
    final bool hitChildren = hitTestChildren(result, position: position);
    entry.candidates = _collectCandidates(result.path, after: entry);
    return hitChildren || hitTestSelf(position);
  }

  List<_ScrollableCandidate> _collectCandidates(
    Iterable<HitTestEntry> path, {
    required HitTestEntry after,
  }) {
    final List<_ScrollableCandidate> candidates = <_ScrollableCandidate>[];
    final Set<ScrollPosition> seen = <ScrollPosition>{};
    bool passedSelf = false;

    for (final HitTestEntry item in path) {
      if (!passedSelf) {
        if (identical(item, after)) {
          passedSelf = true;
        }
        continue;
      }

      final HitTestTarget target = item.target;
      if (target is _RenderScrollableAnchor) {
        final ScrollPosition? pos = target.resolvePosition();
        if (pos != null &&
            axisDirectionToAxis(target.details.direction) == Axis.vertical &&
            seen.add(pos)) {
          candidates.add(
            _ScrollableCandidate(
              position: pos,
              axisDirection: target.details.direction,
            ),
          );
        }
      } else if (target is RenderViewportBase) {
        final ViewportOffset offset = target.offset;
        if (target.axis == Axis.vertical &&
            offset is ScrollPosition &&
            seen.add(offset)) {
          candidates.add(
            _ScrollableCandidate(
              position: offset,
              axisDirection: target.axisDirection,
            ),
          );
        }
      }
    }
    return candidates;
  }

  static bool _isPositionMounted(ScrollPosition position) {
    final ScrollContext ctx = position.context;
    if (ctx is ScrollableState && !ctx.mounted) {
      return false;
    }
    return position.hasPixels && position.hasContentDimensions;
  }

  static double _effectiveDelta(
    _ScrollableCandidate candidate,
    double rawDy,
  ) {
    return axisDirectionIsReversed(candidate.axisDirection) ? -rawDy : rawDy;
  }

  static bool _canScrollInDirection(ScrollPosition position, double delta) {
    if (delta > 0.0) {
      return position.pixels < position.maxScrollExtent - 0.5;
    }
    if (delta < 0.0) {
      return position.pixels > position.minScrollExtent + 0.5;
    }
    return false;
  }

  _ScrollableCandidate? _pickCandidate(
    List<_ScrollableCandidate> candidates,
    double rawDy,
  ) {
    for (final _ScrollableCandidate candidate in candidates) {
      final ScrollPosition position = candidate.position;
      if (!_isPositionMounted(position)) continue;
      if (!position.physics.shouldAcceptUserOffset(position)) continue;
      final double delta = _effectiveDelta(candidate, rawDy);
      if (_canScrollInDirection(position, delta)) {
        return candidate;
      }
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) return;
    final double dy = event.scrollDelta.dy;
    if (dy == 0.0) return;
    // Пропускаем только мелкие непрерывные субпиксельные свайпы настоящего тачпада.
    if (event.kind == PointerDeviceKind.trackpad && dy.abs() < 8.0) return;
    if (entry is! _SmoothWheelHitTestEntry) return;

    final _ScrollableCandidate? candidate = _pickCandidate(
      entry.candidates,
      dy,
    );
    if (candidate == null) return;

    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (PointerSignalEvent rawEvent) {
        _handleResolvedPointerScroll(
          rawEvent as PointerScrollEvent,
          candidate,
        );
      },
    );
  }

  void _handleResolvedPointerScroll(
    PointerScrollEvent event,
    _ScrollableCandidate candidate,
  ) {
    final ScrollPosition position = candidate.position;
    if (!_isPositionMounted(position)) return;

    final double rawDelta = _effectiveDelta(candidate, event.scrollDelta.dy);
    if (rawDelta == 0.0) return;

    final double nowMs = _nowMs;
    final int direction = rawDelta > 0.0 ? 1 : -1;

    if (identical(_lastWheelPosition, position) &&
        _lastWheelDirection == direction &&
        _lastWheelTimeMs != null &&
        (nowMs - _lastWheelTimeMs!) < kFastSpinWindowMs) {
      final double maxBoost = math.max(1.0, kFastSpinMaxBoost);
      _spinBoost = (_spinBoost + (maxBoost - 1.0) / 4.0).clamp(1.0, maxBoost);
    } else {
      _spinBoost = 1.0;
    }
    _lastWheelPosition = position;
    _lastWheelTimeMs = nowMs;
    _lastWheelDirection = direction;

    final double effectiveDelta = rawDelta * kWheelStepMultiplier * _spinBoost;

    _GlideState? state = _activeGlides[position];
    // Если скролл сдвинули извне (drag скроллбара / внешний jumpTo),
    // сбрасываем прошлое накопление и стартуем от фактической позиции.
    if (state != null &&
        state.lastWrittenPixels != null &&
        (position.pixels - state.lastWrittenPixels!).abs() > 2.0) {
      _activeGlides.remove(position);
      state = null;
    }

    if (state != null) {
      // Обновляем текущую мгновенную позицию по кривой до nowMs перед retargeting'ом,
      // чтобы избежать скачка назад или рывка при смене цели на лету.
      final double progress = kScrollDurationMs <= 0
          ? 1.0
          : ((nowMs - state.animStartTimeMs) / kScrollDurationMs)
              .clamp(0.0, 1.0);
      final double eased = _easeOutCubic(progress);
      state.currentPixels = (state.startPixels +
              (state.targetPixels - state.startPixels) * eased)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
    } else {
      state = _GlideState(
        startPixels: position.pixels,
        currentPixels: position.pixels,
        targetPixels: position.pixels,
        animStartTimeMs: nowMs,
        lastWrittenPixels: position.pixels,
      );
    }

    state.startPixels = state.currentPixels;
    state.targetPixels = (state.targetPixels + effectiveDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    state.animStartTimeMs = nowMs;

    event.respond(allowPlatformDefault: false);

    if ((state.targetPixels - state.currentPixels).abs() < 0.05 &&
        !_activeGlides.containsKey(position)) {
      return;
    }

    _activeGlides[position] = state;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (!attached || _activeGlides.isEmpty) {
      _stopTicker();
      return;
    }

    final double nowMs = _nowMs;
    final List<ScrollPosition> toRemove = <ScrollPosition>[];

    for (final MapEntry<ScrollPosition, _GlideState> entry
        in _activeGlides.entries.toList()) {
      final ScrollPosition position = entry.key;
      final _GlideState state = entry.value;

      if (!_isPositionMounted(position)) {
        toRemove.add(position);
        continue;
      }

      // Ручное перетаскивание скроллбара или внешний jumpTo (> 2px).
      if (state.lastWrittenPixels != null &&
          (position.pixels - state.lastWrittenPixels!).abs() > 2.0) {
        toRemove.add(position);
        continue;
      }

      final double clampedTarget = state.targetPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      state.targetPixels = clampedTarget;

      // Детерминированная кривая Chromium EaseOutCubic: мгновенный чёткий отклик
      // в t = 0 без фазовой задержки и плавный выкат в t = 1.0.
      final double t = kScrollDurationMs <= 0
          ? 1.0
          : ((nowMs - state.animStartTimeMs) / kScrollDurationMs)
              .clamp(0.0, 1.0);
      final double eased = _easeOutCubic(t);
      final double nextPixels = (state.startPixels +
              (clampedTarget - state.startPixels) * eased)
          .clamp(position.minScrollExtent, position.maxScrollExtent);

      state.currentPixels = nextPixels;
      state.lastWrittenPixels = nextPixels;
      if (position.pixels != nextPixels) {
        position.jumpTo(nextPixels);
      }

      if (t >= 1.0) {
        if (position.pixels != clampedTarget) {
          position.jumpTo(clampedTarget);
        }
        toRemove.add(position);
      }
    }

    for (final ScrollPosition pos in toRemove) {
      _activeGlides.remove(pos);
    }
    if (_activeGlides.isEmpty) {
      _stopTicker();
    }
  }

  void _stopTicker() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
  }
}

class _ScrollableAnchor extends SingleChildRenderObjectWidget {
  final BuildContext scrollableContext;
  final ScrollableDetails details;

  const _ScrollableAnchor({
    required this.scrollableContext,
    required this.details,
    required super.child,
  });

  @override
  _RenderScrollableAnchor createRenderObject(BuildContext context) {
    return _RenderScrollableAnchor(
      scrollableContext: scrollableContext,
      details: details,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollableAnchor renderObject,
  ) {
    renderObject.scrollableContext = scrollableContext;
    renderObject.details = details;
  }
}

class _RenderScrollableAnchor extends RenderProxyBox {
  BuildContext scrollableContext;
  ScrollableDetails details;

  _RenderScrollableAnchor({
    required this.scrollableContext,
    required this.details,
  });

  ScrollPosition? resolvePosition() {
    final ctx = scrollableContext;
    if (ctx is StatefulElement && ctx.mounted && ctx.state is ScrollableState) {
      return (ctx.state as ScrollableState).position;
    }
    final controller = details.controller;
    if (controller != null &&
        controller.hasClients &&
        controller.positions.length == 1) {
      return controller.position;
    }
    return null;
  }
}
