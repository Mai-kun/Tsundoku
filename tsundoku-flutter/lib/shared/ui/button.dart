/// 1:1 port of `mediatracker-ui/src/shared/ui/Button.svelte`.
///
/// Colors come strictly from tokens.css primitives. `active:scale-[0.98]`,
/// holdProgress fill (bg-danger/30, origin-left) и loading-спиннер сохранены
/// 1-в-1; hover-эффекты — через InkWell/HoverRegion.
library;

import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_theme.dart';
import '../theme/tsundoku_tokens.dart';

/// `"primary" | "secondary" | "ghost" | "outline" | "danger"`.
enum ButtonVariant { primary, secondary, ghost, outline, danger }

/// `"xs" | "sm" | "md" | "lg" | "icon"`.
enum ButtonSize { xs, sm, md, lg, icon }

/// Geometry 1-в-1 с sizeClasses: высота (h-*), gap, radius, padding, шрифт.
class ButtonGeometry {
  final double height;
  final double gap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const ButtonGeometry({
    required this.height,
    required this.gap,
    required this.radius,
    required this.padding,
    required this.fontSize,
  });

  static const ButtonGeometry xs = ButtonGeometry(
      height: 24,
      gap: 4,
      radius: 6,
      padding: EdgeInsets.symmetric(horizontal: 8),
      fontSize: 11);
  static const ButtonGeometry sm = ButtonGeometry(
      height: 32,
      gap: 6,
      radius: 6,
      padding: EdgeInsets.symmetric(horizontal: 12),
      fontSize: 12);
  static const ButtonGeometry md = ButtonGeometry(
      height: 36,
      gap: 8,
      radius: 8,
      padding: EdgeInsets.symmetric(horizontal: 14),
      fontSize: 14);
  static const ButtonGeometry lg = ButtonGeometry(
      height: 40,
      gap: 8,
      radius: 8,
      padding: EdgeInsets.symmetric(horizontal: 16),
      fontSize: 14);
  static const ButtonGeometry icon = ButtonGeometry(
      height: 36, gap: 0, radius: 8, padding: EdgeInsets.zero, fontSize: 14);
}

/// Цвета варианта: (background, text) — hover считается в [build].
({Color background, Color text}) _variantColors(
    ButtonVariant variant, TsundokuTheme th) {
  switch (variant) {
    case ButtonVariant.primary:
      return (background: th.accent, text: const Color(0xFFFFFFFF));
    case ButtonVariant.secondary:
      return (background: th.bgElevated, text: th.textPrimary);
    case ButtonVariant.ghost:
      return (background: Colors.transparent, text: th.textMuted);
    case ButtonVariant.outline:
      return (background: Colors.transparent, text: th.textPrimary);
    case ButtonVariant.danger:
      return (background: th.danger, text: const Color(0xFFFFFFFF));
  }
}

/// `<button>` с вариантами/размерами/loading/holdProgress-fill.
class TsundokuButton extends StatefulWidget {
  final ButtonVariant variant;
  final ButtonSize size;
  final bool loading;
  /// Collapse to a square (w = h of the chosen size) for icon-only buttons.
  final bool iconOnly;
  /// 0..1 hold-to-confirm fill (holdToDelete controller); null hides it.
  final double? holdProgress;
  final bool disabled;
  final VoidCallback? onPressed;
  final Widget child;

  const TsundokuButton({
    super.key,
    this.variant = ButtonVariant.secondary,
    this.size = ButtonSize.md,
    this.loading = false,
    this.iconOnly = false,
    this.holdProgress,
    this.disabled = false,
    this.onPressed,
    required this.child,
  });

  @override
  State<TsundokuButton> createState() => _TsundokuButtonState();
}

class _TsundokuButtonState extends State<TsundokuButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final geometry = widget.size == ButtonSize.icon
        ? ButtonGeometry.icon
        : switch (widget.size) {
            ButtonSize.xs => ButtonGeometry.xs,
            ButtonSize.sm => ButtonGeometry.sm,
            ButtonSize.md => ButtonGeometry.md,
            ButtonSize.lg => ButtonGeometry.lg,
            ButtonSize.icon => ButtonGeometry.icon,
          };
    final (:background, :text) = _variantColors(widget.variant, th);
    final enabled = !widget.disabled && !widget.loading;

    Widget label = DefaultTextStyle.merge(
      style: TextStyle(
          fontSize: geometry.fontSize,
          fontWeight: FontWeight.w500,
          color: text),
      child: widget.child,
    );

    if (widget.loading) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: text), // LoaderCircle size-4
          ),
          if (widget.size != ButtonSize.icon) SizedBox(width: geometry.gap),
          if (widget.size != ButtonSize.icon) label,
        ],
      );
    }

    final borderSide = switch (widget.variant) {
      ButtonVariant.secondary => BorderSide(color: th.borderSubtle),
      ButtonVariant.outline => BorderSide(color: th.borderStrong),
      _ => BorderSide.none,
    };

    final button = Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(geometry.radius),
        side: borderSide,
      ),
      child: InkWell(
        onTap: enabled ? widget.onPressed : null,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(geometry.radius),
        hoverColor: widget.variant == ButtonVariant.primary
            ? th.accentHover // hover:bg-accent-hover
            : th.bgHover, // hover:bg-hover
        child: Container(
          height: geometry.height,
          // iconOnly: квадрат w = h, p-0; иначе — паддинги sizeClasses.
          padding: (widget.iconOnly || widget.size == ButtonSize.icon)
              ? EdgeInsets.zero
              : geometry.padding,
          constraints: BoxConstraints(
            minWidth: (widget.iconOnly || widget.size == ButtonSize.icon)
                ? geometry.height
                : 0,
            minHeight: (widget.iconOnly || widget.size == ButtonSize.icon)
                ? geometry.height
                : 0,
          ),
          child: Center(child: label),
        ),
      ),
    );

    return Opacity(
      opacity: widget.disabled || widget.loading ? 0.5 : 1.0, // disabled:opacity-50
      child: AnimatedScale(
        scale: enabled && _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: TsundokuPalette.easeTap,
        child: Stack(
          children: [
            // holdProgress fill: bg-danger/30, origin-left, -z-10 под лейблом.
            if (widget.holdProgress != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(geometry.radius),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft, // origin-left
                      widthFactor: widget.holdProgress!.clamp(0.0, 1.0),
                      child: Container(
                          color: th.danger.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
              ),
            button,
          ],
        ),
      ),
    );
  }
}
