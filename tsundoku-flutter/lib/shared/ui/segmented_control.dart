import 'package:material_ui/material_ui.dart';

import '../theme/tsundoku_tokens.dart';

class SegmentedOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentedOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Unified segmented control (pill tabs) strictly sized to its content (not stretched
/// full-width unless [expand] is explicitly set to true).
/// Matches Svelte styling:
/// - Background `bgCard` or `#131720` / `white/[0.04]`, border `white/5`, rounded 12px, padding 3px/4px.
/// - Selected tab: `bgAccent` (or custom [activeColor]), font-weight 600, text white.
/// - Inactive tabs: transparent, text-muted, font-weight 500, hover: text-ink.
class TsundokuSegmentedControl<T> extends StatelessWidget {
  final List<SegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;
  final Color? backgroundColor;
  final Color? activeColor;
  final Color? activeTextColor;
  final Color? inactiveTextColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const TsundokuSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.backgroundColor,
    this.activeColor,
    this.activeTextColor,
    this.inactiveTextColor,
    this.fontSize = 13.0,
    this.padding = const EdgeInsets.all(3.0),
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final bg = backgroundColor ?? th.bgCard;
    final actBg = activeColor ?? th.accent;
    final actText = activeTextColor ?? Colors.white;
    final inactText = inactiveTextColor ?? th.textMuted;

    final children = <Widget>[];
    for (int i = 0; i < options.length; i++) {
      final opt = options[i];
      final isSelected = opt.value == value;

      Widget button = InkWell(
        onTap: () => onChanged(opt.value),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? actBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(51), // withOpacity 0.2
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (opt.icon != null) ...[
                Icon(
                  opt.icon,
                  size: fontSize + 1,
                  color: isSelected ? actText : inactText,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                opt.label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? actText : inactText,
                ),
              ),
            ],
          ),
        ),
      );

      if (expand) {
        button = Expanded(child: button);
      }
      children.add(button);
      if (i < options.length - 1) {
        children.add(const SizedBox(width: 4));
      }
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14FFFFFF)), // white/8
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Unified section header:
/// `UPPERCASE`, `11px`, `letterSpacing: 0.8`, `FontWeight.w600`, `text-muted`.
class TsundokuSectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const TsundokuSectionHeader(
    this.title, {
    super.key,
    this.padding = EdgeInsets.zero,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    final text = Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: th.textMuted,
      ),
    );

    if (trailing == null) {
      return Padding(padding: padding, child: text);
    }

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          text,
          trailing!,
        ],
      ),
    );
  }
}
