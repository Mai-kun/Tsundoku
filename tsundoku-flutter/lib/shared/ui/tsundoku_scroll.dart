/// Единая конфигурация и хелперы плавного скролла колёсиком мыши на базе
/// `package:flutter_smooth_wheel_scroll`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_smooth_wheel_scroll/flutter_smooth_wheel_scroll.dart';

export 'package:flutter_smooth_wheel_scroll/flutter_smooth_wheel_scroll.dart'
    show
        ScrollbarController,
        SmoothScrollController,
        SmoothWheelBinding,
        SmoothWheelBindingMixin,
        WheelMotion;

/// Множитель шага колеса мыши для всего приложения.
const double kTsundokuWheelScale = 1.00;

/// Кривая и длительность доводки колеса мыши для всего приложения.
const WheelMotion kTsundokuWheelMotion = WheelMotion.curve(
  duration: Duration(milliseconds: 400),
  curve: Curves.easeOutCubic,
);

/// Создаёт [SmoothScrollController] с единой конфигурацией приложения.
SmoothScrollController createTsundokuScrollController({
  double initialScrollOffset = 0.0,
  bool keepScrollOffset = true,
  String? debugLabel,
}) {
  return SmoothScrollController(
    initialScrollOffset: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    debugLabel: debugLabel,
    motion: kTsundokuWheelMotion,
  );
}

/// Оборачивает поддерево в [PrimaryScrollController] с [SmoothScrollController],
/// чтобы верхнеуровневый скроллер без явного `controller` получил плавный
/// скролл колёсиком на всех платформах (включая Linux/Windows/macOS/Web).
class TsundokuSmoothScrollScope extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;
  final String? debugLabel;

  const TsundokuSmoothScrollScope({
    super.key,
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.debugLabel,
  });

  @override
  State<TsundokuSmoothScrollScope> createState() =>
      _TsundokuSmoothScrollScopeState();
}

class _TsundokuSmoothScrollScopeState extends State<TsundokuSmoothScrollScope> {
  late final SmoothScrollController _controller =
      createTsundokuScrollController(debugLabel: widget.debugLabel);

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

/// Drop-in замена вертикального [SingleChildScrollView] со встроенным
/// [SmoothScrollController] (если внешний [controller] не передан).
class TsundokuSmoothScrollView extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final Clip clipBehavior;
  final SmoothScrollController? controller;
  final String? debugLabel;

  const TsundokuSmoothScrollView({
    super.key,
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.physics,
    this.clipBehavior = Clip.hardEdge,
    this.controller,
    this.debugLabel,
  });

  @override
  State<TsundokuSmoothScrollView> createState() =>
      _TsundokuSmoothScrollViewState();
}

class _TsundokuSmoothScrollViewState extends State<TsundokuSmoothScrollView> {
  SmoothScrollController? _ownedController;

  SmoothScrollController get _effectiveController =>
      widget.controller ??
      (_ownedController ??= createTsundokuScrollController(
        debugLabel: widget.debugLabel,
      ));

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      padding: widget.padding,
      physics: widget.physics,
      clipBehavior: widget.clipBehavior,
      controller: _effectiveController,
      child: widget.child,
    );
  }
}
