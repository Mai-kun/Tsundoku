/// 1:1 port of `mediatracker-ui/src/shared/ui/Button.svelte`.
///
/// Colors come strictly from tokens.css primitives. `active:scale-[0.98]`,
/// holdProgress fill (bg-danger/30, origin-left) и loading-спиннер сохранены
/// 1-в-1; hover-эффекты — через InkWell/HoverRegion.
library;

import 'package:material_ui/material_ui.dart';

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
class TsundokuButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final geometry = size == ButtonSize.icon
        ? ButtonGeometry.icon
        : switch (size) {
            ButtonSize.xs => ButtonGeometry.xs,
            ButtonSize.sm => ButtonGeometry.sm,
            ButtonSize.md => ButtonGeometry.md,
            ButtonSize.lg => ButtonGeometry.lg,
            ButtonSize.icon => ButtonGeometry.icon,
          };
    final (:background, :text) = _variantColors(variant, th);
    final enabled = !disabled && !loading;

    Widget label = DefaultTextStyle.merge(
      style: TextStyle(
          fontSize: geometry.fontSize,
          fontWeight: FontWeight.w500,
          color: text),
      child: child,
    );

    if (loading) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: text), // LoaderCircle size-4
          ),
          if (size != ButtonSize.icon) SizedBox(width: geometry.gap),
          if (size != ButtonSize.icon) label,
        ],
      );
    }

    final borderSide = switch (variant) {
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
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(geometry.radius),
        hoverColor: variant == ButtonVariant.primary
            ? th.accentHover // hover:bg-accent-hover
            : th.bgHover, // hover:bg-hover
        child: Container(
          height: geometry.height,
          // iconOnly: квадрат w = h, p-0; иначе — паддинги sizeClasses.
          padding: (iconOnly || size == ButtonSize.icon)
              ? EdgeInsets.zero
              : geometry.padding,
          constraints: BoxConstraints(
            minWidth: (iconOnly || size == ButtonSize.icon)
                ? geometry.height
                : 0,
            minHeight: (iconOnly || size == ButtonSize.icon)
                ? geometry.height
                : 0,
          ),
          child: Center(child: label),
        ),
      ),
    );

    return Opacity(
      opacity: disabled || loading ? 0.5 : 1.0, // disabled:opacity-50
      child: Stack(
        children: [
          // holdProgress fill: bg-danger/30, origin-left, -z-10 под лейблом.
          if (holdProgress != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(geometry.radius),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft, // origin-left
                    widthFactor: holdProgress!.clamp(0.0, 1.0),
                    child: Container(
                        color: th.danger.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),
          button,
        ],
      ),
    );
  }
}
