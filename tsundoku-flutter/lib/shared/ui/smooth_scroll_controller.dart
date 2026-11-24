import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// [ScrollController] с плавной интерполяцией скролла колёсиком мыши.
///
/// Стандартный [ScrollPositionWithSingleContext.pointerScroll] применяет дельту
/// колеса мгновенно за один кадр (`forcePixels`), из-за чего на 120–144 Гц
/// мониторах прокрутка выглядит ступенчатой. Здесь каждый [PointerScrollEvent]
/// накапливается в целевой позиции и сглаживается через [Ticker] на частоте
/// обновления экрана, не затрагивая перетаскивание, тачпад и [jumpTo]/[animateTo].
class SmoothScrollController extends ScrollController {
  /// Скорость экспоненциального сглаживания (в 1/сек). Чем больше — тем быстрее
  /// и жёстче отклик; 18.0 даёт ~200 мс доводку.
  final double smoothing;

  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    super.onAttach,
    super.onDetach,
    this.smoothing = 18.0,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      smoothing: smoothing,
    );
  }
}

/// Оборачивает поддерево в [PrimaryScrollController] с [SmoothScrollController],
/// чтобы верхнеуровневый [SingleChildScrollView] / [ListView] без явного
/// `controller` автоматически получил плавный скролл колёсиком.
class SmoothScrollScope extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;
  final double smoothing;

  const SmoothScrollScope({
    super.key,
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.smoothing = 18.0,
  });

  @override
  State<SmoothScrollScope> createState() => _SmoothScrollScopeState();
}

class _SmoothScrollScopeState extends State<SmoothScrollScope> {
  late final SmoothScrollController _controller = SmoothScrollController(
    smoothing: widget.smoothing,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _controller,
      scrollDirection: widget.scrollDirection,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: widget.child,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  final double smoothing;

  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.smoothing,
  });

  void _updateWheelDirection(double diff) {
    updateUserScrollDirection(
      -diff > 0.0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
  }

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }
    if (!physics.shouldAcceptUserOffset(this)) {
      return;
    }

    final currentActivity = activity;
    if (currentActivity is _SmoothWheelScrollActivity) {
      final double nextTarget = math.min(
        math.max(currentActivity.targetPixels + delta, minScrollExtent),
        maxScrollExtent,
      );
      if (nextTarget != currentActivity.targetPixels || nextTarget != pixels) {
        currentActivity.updateTarget(nextTarget);
      }
      return;
    }

    final double targetPixels = math.min(
      math.max(pixels + delta, minScrollExtent),
      maxScrollExtent,
    );
    if (targetPixels == pixels) {
      return;
    }

    beginActivity(
      _SmoothWheelScrollActivity(
        this,
        initialTarget: targetPixels,
        vsync: context.vsync,
        smoothing: smoothing,
      ),
    );
  }
}

class _SmoothWheelScrollActivity extends ScrollActivity {
  _SmoothWheelScrollActivity(
    _SmoothScrollPosition super.delegate, {
    required double initialTarget,
    required TickerProvider vsync,
    required this.smoothing,
  }) : _targetPixels = initialTarget {
    _ticker = vsync.createTicker(_tick);
    _ticker.start();
  }

  final double smoothing;
  late final Ticker _ticker;
  double _targetPixels;
  int _lastElapsedMicros = 0;
  double _velocity = 0.0;

  double get targetPixels => _targetPixels;

  void updateTarget(double nextTarget) {
    _targetPixels = nextTarget;
  }

  void _tick(Duration elapsed) {
    final pos = delegate;
    if (pos is! _SmoothScrollPosition || !pos.hasPixels) {
      pos.goBallistic(0.0);
      return;
    }

    final double target = math.min(
      math.max(_targetPixels, pos.minScrollExtent),
      pos.maxScrollExtent,
    );
    _targetPixels = target;

    final int dtMicros = elapsed.inMicroseconds - _lastElapsedMicros;
    _lastElapsedMicros = elapsed.inMicroseconds;
    final double dt = dtMicros <= 0
        ? (1.0 / 60.0)
        : (dtMicros / 1000000.0).clamp(0.001, 0.05);

    final double current = pos.pixels;
    final double diff = target - current;

    if (diff.abs() <= 0.35) {
      _velocity = 0.0;
      if (current != target) {
        pos._updateWheelDirection(diff);
        pos.setPixels(target);
      }
      pos.goBallistic(0.0);
      return;
    }

    final double factor = 1.0 - math.exp(-smoothing * dt);
    final double nextPixels = current + diff * factor;
    _velocity = (nextPixels - current) / dt;
    pos._updateWheelDirection(diff);
    final double overscroll = pos.setPixels(nextPixels);
    if (overscroll != 0.0) {
      _velocity = 0.0;
      pos.goBallistic(0.0);
    }
  }

  @override
  bool get isScrolling => true;

  @override
  bool get shouldIgnorePointer => false;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
