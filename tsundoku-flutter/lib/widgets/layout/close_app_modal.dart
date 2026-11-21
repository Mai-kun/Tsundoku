/// 1:1 port of `mediatracker-ui/src/widgets/layout/CloseAppModal.svelte`.
///
/// Оверлей выбора действия при закрытии окна: «в трей» (indigo) / «полный
/// выход» (rose), Apply (exitApp/closeToTray — биндинги от App: AppExit
/// колбек-паттерн порт-а + closeWindow через PlatformService-фасад),
/// Cancel/Esc → onClose.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/utils/app_exit.dart';

enum _CloseChoice { tray, exit }

class CloseAppModal extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  /// Биндинги выхода (AppExit + фасад окна): App решает, как закрывать окно
  /// и показывать тост (колбек-паттерн appExit, решение #10-семейства).
  final AppExit? appExit;
  final Future<void> Function() closeWindow;
  final void Function({required String title, required String description})
      showToast;

  const CloseAppModal({
    super.key,
    required this.onClose,
    required this.closeWindow,
    required this.showToast,
    this.appExit,
  });

  @override
  ConsumerState<CloseAppModal> createState() => _CloseAppModalState();
}

class _CloseAppModalState extends ConsumerState<CloseAppModal> {
  _CloseChoice _choice = _CloseChoice.tray; // choice = $state("tray")
  bool _isApplying = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // svelte:window onkeydown работает при любом фокусе; в Flutter узлу
    // нужен фокус — забираем после монтирования.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _isApplying = true);
    try {
      if (_choice == _CloseChoice.exit) {
        await widget.appExit?.exitApp(
          closeWindow: widget.closeWindow,
          showStoppedScreen: (_) {},
        );
        return;
      }
      widget.appExit?.closeToTray(
        closeWindow: widget.closeWindow,
        showToast: widget.showToast,
      );
      widget.onClose();
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        // svelte:window: Escape → onClose.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: Container(
        color: const Color(0xCC090B10), // bg-[#090b10]/80
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16), // p-4
        child: Container(
          padding: const EdgeInsets.all(20), // p-5
          constraints: const BoxConstraints(maxWidth: 448), // max-w-md
          decoration: BoxDecoration(
            color: const Color(0xF2151A26), // bg-[#151a26]/95
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(color: Colors.white.withAlpha(26)), // white/10
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000), // shadow-black/60
                offset: Offset(0, 25),
                blurRadius: 50,
                spreadRadius: -12,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.tr('closeAppModal.title'),
                style: TextStyle(
                  fontSize: 16, // text-base
                  fontWeight: FontWeight.w700, // font-bold
                  color: th.textPrimary, // text-ink
                ),
              ),
              const SizedBox(height: 16), // mt-4
              _CloseChoiceCard(
                selected: _choice == _CloseChoice.tray,
                title: t.tr('closeAppModal.backgroundTitle'),
                description: t.tr('closeAppModal.backgroundDescription'),
                // tray: indigo-500/60 border, indigo-500/15 bg,
                // ring indigo-500/30, radio indigo-400.
                selectedBorder: const Color(0x996366F1),
                selectedBackground: const Color(0x266366F1),
                ringColor: const Color(0x4D6366F1),
                radioColor: const Color(0xFF818CF4), // indigo-400
                th: th,
                onTap: () => setState(() => _choice = _CloseChoice.tray),
              ),
              const SizedBox(height: 10), // space-y-2.5
              _CloseChoiceCard(
                selected: _choice == _CloseChoice.exit,
                title: t.tr('closeAppModal.exitTitle'),
                description: t.tr('closeAppModal.exitDescription'),
                // exit: rose-500/60 border, rose-500/15 bg,
                // ring rose-500/30, radio rose-400.
                selectedBorder: const Color(0x99F43F5E),
                selectedBackground: const Color(0x26F43F5E),
                ringColor: const Color(0x4DF43F5E),
                radioColor: const Color(0xFFFB7185), // rose-400
                th: th,
                onTap: () => setState(() => _choice = _CloseChoice.exit),
              ),
              Container(
                margin: const EdgeInsets.only(top: 20), // mt-5
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _CancelButton(
                      label: t.tr('common.cancel'),
                      th: th,
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 10), // gap-2.5
                    _ApplyButton(
                      label: t.tr('closeAppModal.apply'),
                      th: th,
                      disabled: _isApplying,
                      onPressed: () => unawaitedApply(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> unawaitedApply() async {
    await _apply();
  }
}

/// Карточка выбора: rounded-xl border p-3.5; выбранная — цветная обводка +
/// заливка + ring; radio 16px (border-4 при выборе).
class _CloseChoiceCard extends StatefulWidget {
  final bool selected;
  final String title;
  final String description;
  final Color selectedBorder;
  final Color selectedBackground;
  final Color ringColor;
  final Color radioColor;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _CloseChoiceCard({
    required this.selected,
    required this.title,
    required this.description,
    required this.selectedBorder,
    required this.selectedBackground,
    required this.ringColor,
    required this.radioColor,
    required this.th,
    required this.onTap,
  });

  @override
  State<_CloseChoiceCard> createState() => _CloseChoiceCardState();
}

class _CloseChoiceCardState extends State<_CloseChoiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final th = widget.th;
    final hovered = _hovered && !selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(14), // p-3.5
          decoration: BoxDecoration(
            color: selected
                ? widget.selectedBackground
                : Colors.white.withAlpha(5), // bg-white/[0.02]
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(
              color: selected
                  ? widget.selectedBorder
                  : hovered
                      ? Colors.white.withAlpha(51) // hover:border-white/20
                      : Colors.white.withAlpha(26), // border-white/10
            ),
            // ring-1 выбранным.
            boxShadow: selected
                ? [BoxShadow(color: widget.ringColor, spreadRadius: 1)]
                : const [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // radio: mt-0.5 h-4 w-4 rounded-full; выбран — border-4.
              Container(
                margin: const EdgeInsets.only(top: 2), // mt-0.5
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? widget.radioColor
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? widget.radioColor
                        : Colors.white.withAlpha(64), // border-white/25
                    width: selected ? 4 : 1, // border-4 / border
                  ),
                ),
              ),
              const SizedBox(width: 12), // gap-3
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14, // text-sm
                        fontWeight: FontWeight.w600, // font-semibold
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2), // mt-0.5
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        height: 1.375, // leading-snug
                        color: th.textMuted, // text-muted
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cancel: rounded-lg border-white/10 px-4 py-2 text-sm font-medium
/// text-slate-300 hover:bg-white/5 hover:text-white.
class _CancelButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onPressed;

  const _CancelButton({
    required this.label,
    required this.th,
    required this.onPressed,
  });

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // px-4 py-2
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withAlpha(13) : Colors.transparent,
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(color: Colors.white.withAlpha(26)), // white/10
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14, // text-sm
              fontWeight: FontWeight.w500, // font-medium
              color: _hovered
                  ? Colors.white
                  : const Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
        ),
      ),
    );
  }
}

/// Apply: bg-accent hover:bg-accent-hover rounded-lg px-4 py-2 text-sm
/// font-semibold text-white; disabled → opacity-50.
class _ApplyButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final bool disabled;
  final VoidCallback onPressed;

  const _ApplyButton({
    required this.label,
    required this.th,
    required this.disabled,
    required this.onPressed,
  });

  @override
  State<_ApplyButton> createState() => _ApplyButtonState();
}

class _ApplyButtonState extends State<_ApplyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    final disabled = widget.disabled;
    final hovered = _hovered && !disabled;

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: disabled ? null : widget.onPressed,
        child: Opacity(
          opacity: disabled ? 0.5 : 1, // disabled:opacity-50
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8), // px-4 py-2
            decoration: BoxDecoration(
              color: hovered ? th.accentHover : th.accent, // bg-accent(-hover)
              borderRadius: BorderRadius.circular(8), // rounded-lg
            ),
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 14, // text-sm
                fontWeight: FontWeight.w600, // font-semibold
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
