/// 1:1 port of `mediatracker-ui/src/shared/ui/Badge.svelte`.
///
/// Brand/source palettes (--color-badge-*, --color-import-*) stay applied from
/// outside; the component owns geometry and token tones only. CSS-классы тонов
/// → цвета 1-в-1 из TsundokuTheme (решение #13).
library;

import 'package:material_ui/material_ui.dart';
import '../theme/tsundoku_tokens.dart';
import '../theme/tsundoku_theme.dart';


/// `"neutral" | "accent" | "info" | "success" | "warning" | "danger"`.
enum BadgeTone { neutral, accent, info, success, warning, danger }

/// `"xs" | "sm"`.
enum BadgeSize { xs, sm }

/// Tone → (border, background, text) из tokens.css 1-в-1.
({Color border, Color background, Color text}) _toneColors(
    BadgeTone tone, TsundokuTheme th) {
  switch (tone) {
    case BadgeTone.neutral:
      // border-subtle bg-hover text-secondary
      return (
        border: th.borderSubtle,
        background: th.bgHover,
        text: th.textSecondary,
      );
    case BadgeTone.accent:
      // border-accent-bright/30 bg-accent-bright/15 text-accent-soft
      return (
        border: th.accentBright.withValues(alpha: 0.3),
        background: th.accentBright.withValues(alpha: 0.15),
        text: th.accentSoft,
      );
    case BadgeTone.info:
      // border-info-line/30 bg-info-line/10 text-info-soft
      return (
        border: TsundokuPalette.infoLine.withValues(alpha: 0.3),
        background: TsundokuPalette.infoLine.withValues(alpha: 0.1),
        text: TsundokuPalette.infoSoft,
      );
    case BadgeTone.success:
      // border-success-line/30 bg-success-line/10 text-success-soft
      return (
        border: TsundokuPalette.successLine.withValues(alpha: 0.3),
        background: TsundokuPalette.successLine.withValues(alpha: 0.1),
        text: TsundokuPalette.successSoft,
      );
    case BadgeTone.warning:
      // border-warning-line/30 bg-warning-line/10 text-warning-text
      return (
        border: TsundokuPalette.warningLine.withValues(alpha: 0.3),
        background: TsundokuPalette.warningLine.withValues(alpha: 0.1),
        text: th.warningText,
      );
    case BadgeTone.danger:
      // border-danger/30 bg-danger-soft text-danger-text
      return (
        border: th.danger.withValues(alpha: 0.3),
        background: th.dangerSoft,
        text: th.dangerText,
      );
  }
}

/// Tone → геометрия из sizeClasses 1-в-1 (px/py → EdgeInsets, radius-md = 6).
EdgeInsetsGeometry _sizePadding(BadgeSize size) {
  switch (size) {
    case BadgeSize.xs:
      // px-1.5 py-0.5 (0.25rem scale): 6px / 2px.
      return const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    case BadgeSize.sm:
      // px-2 py-0.5: 8px / 2px.
      return const EdgeInsets.symmetric(horizontal: 8, vertical: 2);
  }
}

double _sizeFont(BadgeSize size) => size == BadgeSize.xs ? 10 : 12;

/// `<span class="inline-flex items-center whitespace-nowrap border font-medium">`.
class TsundokuBadge extends StatelessWidget {
  final BadgeTone tone;
  final BadgeSize size;
  final Widget child;

  const TsundokuBadge({
    super.key,
    this.tone = BadgeTone.neutral,
    this.size = BadgeSize.sm,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final colors = _toneColors(tone, th);
    return Container(
      padding: _sizePadding(size),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(TsundokuPalette.radiusSelector),
        color: colors.background,
      ),
      constraints: const BoxConstraints(minWidth: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: DefaultTextStyle(
              style: TextStyle(
                fontSize: _sizeFont(size),
                fontWeight: FontWeight.w500,
                color: colors.text,
                height: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
