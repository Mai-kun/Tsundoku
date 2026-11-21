/// 1:1 port of `mediatracker-ui/src/widgets/media-card/CardProgressControls.svelte`.
///
/// Степпер прогресса в hover-слое карточки: две графитовые кнопки ± 28×28px
/// (rounded-md, border-white/10, bg-[#1a202c]/90, hover-[#252d3d],
/// active-[#2d374a], disabled 40%) + центральный лейбл tabular-nums;
/// errorMessage ошибки запроса — под степпером.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';

class CardProgressControls extends ConsumerWidget {
  final String text;
  final void Function(int delta) onStep;
  final bool decrementDisabled;
  final bool incrementDisabled;

  /// Progress request failure, surfaced under the stepper.
  final Object? error;

  const CardProgressControls({
    super.key,
    required this.text,
    required this.onStep,
    this.decrementDisabled = false,
    this.incrementDisabled = false,
    this.error,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StepButton(
              // aria-label={i18n.t.card.decrement}
              semanticLabel: t.tr('card.decrement'),
              disabled: decrementDisabled,
              onPressed: () => onStep(-1),
              icon: LucideIcons.minus, // Minus size={14}
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8), // px-2
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: Color(0xE6FFFFFF), // text-white/90
                    // tabular-nums
                    fontFeatures: [FontFeature.tabularFigures()],
                    shadows: [
                      // drop-shadow-sm
                      Shadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 1),
                    ],
                  ),
                ),
              ),
            ),
            _StepButton(
              semanticLabel: t.tr('card.increment'),
              disabled: incrementDisabled,
              onPressed: () => onStep(1),
              icon: LucideIcons.plus, // Plus size={14}
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // role="alert"
              errorMessage(error!, locale),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12, // text-xs
                height: 16 / 12, // leading-4
                color: Color(0xFFFDA4AF), // text-rose-300
              ),
            ),
          ),
      ],
    );
  }
}

/// Кнопка ± : tap-эффект (active:bg-[#2d374a]) через hover/press-состояние.
class _StepButton extends StatefulWidget {
  final String semanticLabel;
  final bool disabled;
  final VoidCallback onPressed;
  final IconData icon;

  const _StepButton({
    required this.semanticLabel,
    required this.disabled,
    required this.onPressed,
    required this.icon,
  });

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled;
    final hovered = _hovered && !disabled;
    final pressed = _pressed && !disabled;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: disabled ? null : widget.onPressed,
          onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            width: 28, // h-7 w-7
            height: 28,
            padding: const EdgeInsets.all(7), // 14px иконка в 28px кнопке
            decoration: BoxDecoration(
              color: pressed
                  ? const Color(0xFF2D374A) // active:bg-[#2d374a]
                  : hovered
                      ? const Color(0xFF252D3D) // hover:bg-[#252d3d]
                      : const Color(0xE61A202C), // bg-[#1a202c]/90
              borderRadius: BorderRadius.circular(6), // rounded-md
              border: Border.all(
                // hover:border-white/20 → border-white/10
                color: hovered
                    ? Colors.white.withAlpha(51)
                    : Colors.white.withAlpha(26),
              ),
              boxShadow: const [
                // shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05)
                BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
              ],
            ),
            child: Opacity(
              opacity: disabled ? 0.4 : 1, // disabled:opacity-40
              child: Icon(
                widget.icon,
                size: 14,
                color: hovered ? Colors.white : const Color(0xFFD4D4D8), // text-zinc-300
              ),
            ),
          ),
        ),
      ),
    );
  }
}
