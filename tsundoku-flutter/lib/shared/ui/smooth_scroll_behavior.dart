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

/// Угловая частота (рад/с) критически демпфированной пружины скролла колесом.
const double kWheelSpringOmega = 20.0;

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
    final Widget wrapped =
        axisDirectionToAxis(details.direction) == Axis.vertical
        ? _ScrollableAnchor(
            scrollableContext: context,
            details: details,
            child: child,
          )
        : child;
    return super.buildOverscrollIndicator(context, wrapped, details);
  }
}

/// Активность плавного скролла колёсиком мыши на 144 Гц тикере.
///
/// Управляется через [ScrollPosition.beginActivity] и обновляет позицию
/// напрямую через [ScrollActivityDelegate.setPixels], не вызывая на каждом
/// кадре `jumpTo()` (`goIdle` -> `didEndScroll` -> `goBallistic`).
///
/// Пока [shouldIgnorePointer] равен `true`, [Scrollable] включает
/// `IgnorePointer` над [Viewport], отключая лишние hover-ребилды карточек
/// под курсором во время прокрутки.
class SmoothWheelScrollActivity extends ScrollActivity {
  SmoothWheelScrollActivity(
    super.delegate, {
    required TickerProvider vsync,
    required double initialPixels,
    required this._targetPixels,
    double initialVelocity = 0.0,
    this._omega = kWheelSpringOmega,
    this._onDisposed,
  }) : _currentPixels = initialPixels,
       _currentVelocity = initialVelocity {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final double _omega;
  final VoidCallback? _onDisposed;
  late final Ticker _ticker;

  double _currentPixels;
  double _targetPixels;
  double _currentVelocity;
  bool _hasFirstTick = false;
  int _lastElapsedMicros = 0;
  bool _disposed = false;

  /// Целевая позиция скролла в логических пикселях.
  double get targetPixels => _targetPixels;

  /// Была ли активность уже завершена и освобождена.
  bool get isDisposed => _disposed;

  /// Добавляет дельту к текущей цели без перезапуска [ScrollActivity]
  /// и с сохранением текущей позиции и скорости.
  void addDelta(double delta) {
    if (_disposed || delta == 0.0) return;
    double nextTarget = _targetPixels + delta;
    final ScrollActivityDelegate d = delegate;
    if (d is ScrollPosition) {
      final ScrollPosition pos = d as ScrollPosition;
      if (pos.hasContentDimensions) {
        nextTarget = nextTarget.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      }
    }
    _targetPixels = nextTarget;
  }

  @override
  bool get isScrolling => true;

  @override
  bool get shouldIgnorePointer => true;

  @override
  double get velocity => _currentVelocity;

  @override
  void resetActivity() {
    delegate.goBallistic(velocity);
  }

  @override
  void dispatchOverscrollNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double overscroll,
  ) {
    OverscrollNotification(
      metrics: metrics,
      context: context,
      overscroll: overscroll,
      velocity: velocity,
    ).dispatch(context);
  }

  void _onTick(Duration elapsed) {
    if (_disposed) return;

    final ScrollActivityDelegate d = delegate;
    final ScrollPosition? pos = d is ScrollPosition ? d as ScrollPosition : null;
    if (pos != null) {
      final ScrollContext ctx = pos.context;
      if (ctx is ScrollableState && !ctx.mounted) {
        dispose();
        return;
      }
      if (!pos.hasPixels || !pos.hasContentDimensions) {
        d.goIdle();
        return;
      }
      if ((pos.pixels - _currentPixels).abs() > 0.01) {
        _currentPixels = pos.pixels;
      }
      _targetPixels =
          _targetPixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    }

    final int elapsedMicros = elapsed.inMicroseconds;
    final double dt;
    if (!_hasFirstTick) {
      _hasFirstTick = true;
      _lastElapsedMicros = elapsedMicros;
      dt = elapsedMicros > 0
          ? (elapsedMicros / 1000000.0).clamp(0.001, 0.05)
          : (1.0 / 120.0);
    } else {
      final int deltaMicros = elapsedMicros - _lastElapsedMicros;
      _lastElapsedMicros = elapsedMicros;
      if (deltaMicros <= 0) return;
      dt = (deltaMicros / 1000000.0).clamp(0.001, 0.05);
    }

    // Точное аналитическое решение критически демпфированной пружины
    // (C1-непрерывность позиции и скорости при любом ретаргетинге и FPS).
    final double y0 = _currentPixels - _targetPixels;
    final double c2 = _currentVelocity + _omega * y0;
    final double decay = math.exp(-_omega * dt);
    final double nextY = (y0 + c2 * dt) * decay;
    final double nextPixels = _targetPixels + nextY;
    final double nextVelocity = (c2 - _omega * (y0 + c2 * dt)) * decay;

    if ((_targetPixels - nextPixels).abs() < 0.25 &&
        nextVelocity.abs() < 25.0) {
      _currentPixels = _targetPixels;
      _currentVelocity = 0.0;
      if (pos == null || pos.pixels != _targetPixels) {
        d.setPixels(_targetPixels);
      }
      if (!_disposed) {
        d.goIdle();
      }
      return;
    }

    _currentPixels = nextPixels;
    _currentVelocity = nextVelocity;
    final double overscroll = d.setPixels(nextPixels);
    if (!_disposed && overscroll.abs() > 0.001) {
      _currentVelocity = 0.0;
      d.goIdle();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker.dispose();
    _onDisposed?.call();
    super.dispose();
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
  const TsundokuSmoothWheelInterceptor({super.key, required super.child});

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

class _RenderSmoothWheelInterceptor extends RenderProxyBox {
  late final Stopwatch _clock =
      GestureBinding.instance.samplingClock.stopwatch()..start();
  final Map<ScrollPosition, SmoothWheelScrollActivity> _activeActivities =
      <ScrollPosition, SmoothWheelScrollActivity>{};

  ScrollPosition? _lastWheelPosition;
  double? _lastWheelTimeMs;
  int _lastWheelDirection = 0;
  double _spinBoost = 1.0;

  double get _nowMs => _clock.elapsedMicroseconds / 1000.0;

  @override
  void dispose() {
    for (final SmoothWheelScrollActivity activity
        in _activeActivities.values.toList()) {
      if (!activity.isDisposed &&
          activity.delegate is ScrollPosition &&
          _isPositionMounted(activity.delegate as ScrollPosition)) {
        activity.delegate.goIdle();
      }
    }
    _activeActivities.clear();
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
    final _SmoothWheelHitTestEntry entry = _SmoothWheelHitTestEntry(
      this,
      position,
    );
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
      if (target is! RenderObject) continue;

      // Поднимаемся вверх по дереву от каждого hit-test узла, чтобы гарантированно
      // находить ближайший _RenderScrollableAnchor / RenderViewportBase даже при
      // наведении на вложенные картинки, текст, бейджи и кнопки карточек.
      RenderObject? node = target;
      while (node != null && !identical(node, this)) {
        if (node is _RenderScrollableAnchor) {
          final ScrollPosition? pos = node.resolvePosition();
          if (pos != null &&
              axisDirectionToAxis(node.details.direction) == Axis.vertical &&
              seen.add(pos)) {
            candidates.add(
              _ScrollableCandidate(
                position: pos,
                axisDirection: node.details.direction,
              ),
            );
          }
        } else if (node is RenderViewportBase) {
          final ViewportOffset offset = node.offset;
          if (node.axis == Axis.vertical &&
              offset is ScrollPosition &&
              seen.add(offset)) {
            candidates.add(
              _ScrollableCandidate(
                position: offset,
                axisDirection: node.axisDirection,
              ),
            );
          }
        }
        node = node.parent;
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

  static double _effectiveDelta(_ScrollableCandidate candidate, double rawDy) {
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
      if (position is! ScrollActivityDelegate) continue;
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

    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent rawEvent,
    ) {
      _handleResolvedPointerScroll(rawEvent as PointerScrollEvent, candidate);
    });
  }

  void _handleResolvedPointerScroll(
    PointerScrollEvent event,
    _ScrollableCandidate candidate,
  ) {
    final ScrollPosition position = candidate.position;
    if (position is! ScrollActivityDelegate) return;
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
    event.respond(allowPlatformDefault: false);

    final SmoothWheelScrollActivity? active = _activeActivities[position];
    if (active != null && !active.isDisposed) {
      active.addDelta(effectiveDelta);
      return;
    }

    final double targetPixels = (position.pixels + effectiveDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((targetPixels - position.pixels).abs() < 0.25) {
      return;
    }

    late final SmoothWheelScrollActivity activity;
    activity = SmoothWheelScrollActivity(
      position as ScrollActivityDelegate,
      vsync: position.context.vsync,
      initialPixels: position.pixels,
      targetPixels: targetPixels,
      onDisposed: () {
        if (identical(_activeActivities[position], activity)) {
          _activeActivities.remove(position);
        }
      },
    );
    _activeActivities[position] = activity;
    position.beginActivity(activity);
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
