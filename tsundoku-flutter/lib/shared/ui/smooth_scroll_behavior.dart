import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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
  double currentPixels;
  double smoothedTargetPixels;
  double targetPixels;
  double? lastWrittenPixels;

  _GlideState({
    required this.currentPixels,
    required this.smoothedTargetPixels,
    required this.targetPixels,
    this.lastWrittenPixels,
  });
}

class _RenderSmoothWheelInterceptor extends RenderProxyBox {
  late final Ticker _ticker = Ticker(_onTick);
  final Map<ScrollPosition, _GlideState> _activeGlides =
      <ScrollPosition, _GlideState>{};
  Duration? _lastTickElapsed;

  @override
  void dispose() {
    _ticker.dispose();
    _activeGlides.clear();
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

    final double delta = _effectiveDelta(candidate, event.scrollDelta.dy);
    if (delta == 0.0) return;

    _GlideState? state = _activeGlides[position];
    // Если скролл сдвинули извне (drag скроллбара / внешний jumpTo),
    // сбрасываем прошлое накопление и стартуем от фактической позиции.
    if (state != null &&
        state.lastWrittenPixels != null &&
        (position.pixels - state.lastWrittenPixels!).abs() > 2.0) {
      _activeGlides.remove(position);
      state = null;
    }

    state ??= _GlideState(
      currentPixels: position.pixels,
      smoothedTargetPixels: position.pixels,
      targetPixels: position.pixels,
      lastWrittenPixels: position.pixels,
    );

    state.targetPixels = (state.targetPixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    event.respond(allowPlatformDefault: false);

    if ((state.targetPixels - position.pixels).abs() < 0.5 &&
        !_activeGlides.containsKey(position)) {
      return;
    }

    _activeGlides[position] = state;
    if (!_ticker.isActive) {
      _lastTickElapsed = null;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (!attached || _activeGlides.isEmpty) {
      _stopTicker();
      return;
    }

    final double dt;
    if (_lastTickElapsed == null) {
      dt = elapsed.inMicroseconds > 0
          ? (elapsed.inMicroseconds / 1000000.0).clamp(0.001, 0.05)
          : (1.0 / 144.0);
    } else {
      final int dtMicros =
          elapsed.inMicroseconds - _lastTickElapsed!.inMicroseconds;
      if (dtMicros <= 0) {
        return;
      }
      dt = (dtMicros / 1000000.0).clamp(0.001, 0.05);
    }
    _lastTickElapsed = elapsed;

    // Двухступенчатое сглаживание 2-го порядка: плавный разгон (bell-curve) без
    // резкого стартового удара в первый кадр.
    final double targetFactor = 1.0 - math.exp(-28.0 * dt);
    final double followFactor = 1.0 - math.exp(-22.0 * dt);
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

      state.targetPixels = state.targetPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      state.smoothedTargetPixels = state.smoothedTargetPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      final double rawDiff = state.targetPixels - state.currentPixels;
      final double smoothedDiff =
          state.targetPixels - state.smoothedTargetPixels;

      if (rawDiff.abs() < 0.5 && smoothedDiff.abs() < 0.5) {
        final double finalTarget = state.targetPixels;
        toRemove.add(position);
        if (position.pixels != finalTarget) {
          position.jumpTo(finalTarget);
        }
        continue;
      }

      state.smoothedTargetPixels =
          (state.smoothedTargetPixels + smoothedDiff * targetFactor).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final double followDiff =
          state.smoothedTargetPixels - state.currentPixels;
      state.currentPixels =
          (state.currentPixels + followDiff * followFactor).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      state.lastWrittenPixels = state.currentPixels;
      position.jumpTo(state.currentPixels);
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
    _lastTickElapsed = null;
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
