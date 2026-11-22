/// 1:1 port of `mediatracker-ui/src/shared/ui/ConfirmModal.svelte`.
///
/// Модалка подтверждения: иконка (danger → Trash2, иначе AlertTriangle),
/// заголовок/описание (danger без описания → «действие необратимо»), два
/// взаимоисключающих «запомнить» (навсегда / на час), Cancel/Confirm (lg);
/// Enter → confirm, Esc/фон → cancel. Последний request остаётся снапшотом
/// на время выходной анимации (rendered).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../i18n/index.dart';
import '../theme/tsundoku_tokens.dart';
import 'button.dart';
import 'confirm_dialog.dart';
import 'modal.dart';

/// Вариант иконки/цветов: danger или warning.
class _ConfirmStyle {
  final Color border;
  final Color background;
  final Color text;
  final IconData icon;

  const _ConfirmStyle({
    required this.border,
    required this.background,
    required this.text,
    required this.icon,
  });

  static _ConfirmStyle of(bool danger, TsundokuTheme th) {
    if (danger) {
      return _ConfirmStyle(
        border: th.danger.withAlpha(77), // border-danger/30
        background: th.dangerSoft, // bg-danger-soft
        text: th.dangerText, // text-danger-text
        icon: LucideIcons.trash2, // Trash2 size={19}
      );
    }
    // warning-line/surface — цвета app.css вне ThemeExtension (как
    // score-bg): литералы 1-в-1.
    return _ConfirmStyle(
      border: const Color(0x4DD97706), // border-warning-line/30
      background: const Color(0xFF281E0E), // bg-warning-surface
      text: th.warningText, // text-warning-text
      icon: LucideIcons.triangleAlert, // AlertTriangle size={19}
    );
  }
}

class ConfirmModal extends ConsumerStatefulWidget {
  const ConfirmModal({super.key});

  @override
  ConsumerState<ConfirmModal> createState() => _ConfirmModalState();
}

class _ConfirmModalState extends ConsumerState<ConfirmModal> {
  /// The question must stay visible while the exit animation plays out, so
  /// the last request is kept as a snapshot after the store has settled.
  ConfirmRequest? _rendered;

  /// The two memory checkboxes are mutually exclusive: ticking one unticks
  /// the other, and re-ticking the active one clears both.
  ConfirmRemember _remember = ConfirmRemember.none;

  final FocusNode _dialogBody = FocusNode();

  @override
  void initState() {
    super.initState();
    // Focus lands on the dialog body, not the Cancel button (rAF после
    // монтирования).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(confirmDialogProvider).current != null) {
        _dialogBody.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _dialogBody.dispose();
    super.dispose();
  }

  void _toggleRemember(ConfirmRemember which) {
    setState(() {
      _remember = _remember == which ? ConfirmRemember.none : which;
    });
  }

  void _choose(bool confirmed) {
    ref.read(confirmDialogProvider.notifier).settle(confirmed, _remember);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final pending = ref.watch(confirmDialogProvider).current;

    // $effect: новый request → снапшот + сброс remember.
    if (pending != null && pending.request != _rendered) {
      _rendered = pending.request;
      _remember = ConfirmRemember.none;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dialogBody.requestFocus();
      });
    }

    final rendered = _rendered;

    return KeyboardListener(
      focusNode: _dialogBody,
      onKeyEvent: (event) {
        // svelte:window onkeydown: Enter → confirm.
        if (pending == null) return;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          _choose(true);
        }
      },
      child: TsundokuModal(
        isOpen: pending != null,
        onClose: () => ref.read(confirmDialogProvider.notifier).cancel(),
        size: ModalSize.md,
        contentPadding: EdgeInsets.zero,
        child: rendered == null
            ? const SizedBox.shrink()
            : _ConfirmBody(
                request: rendered,
                remember: _remember,
                t: t,
                onToggleRemember: _toggleRemember,
                onChoose: _choose,
                focusNode: _dialogBody,
              ),
      ),
    );
  }
}

class _ConfirmBody extends ConsumerWidget {
  final ConfirmRequest request;
  final ConfirmRemember remember;
  final I18nDictionary t;
  final void Function(ConfirmRemember which) onToggleRemember;
  final void Function(bool confirmed) onChoose;
  final FocusNode focusNode;

  const _ConfirmBody({
    required this.request,
    required this.remember,
    required this.t,
    required this.onToggleRemember,
    required this.onChoose,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final th = TsundokuTheme.of(context);
    final style = _ConfirmStyle.of(request.danger, th);

    // Узел фокуса живёт на KeyboardListener выше — тело не создаёт свой.
    return Container(
        padding: const EdgeInsets.all(24), // p-6
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, // size-10
                  height: 40,
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius:
                        BorderRadius.circular(12), // rounded-xl
                    border: Border.all(color: style.border),
                  ),
                  child: Icon(style.icon, size: 19, color: style.text),
                ),
                const SizedBox(width: 14), // gap-3.5
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2), // pt-0.5
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.title,
                          style: TextStyle(
                            fontSize: 16, // text-base
                            fontWeight: FontWeight.w700, // font-bold
                            letterSpacing: -0.4, // tracking-tight
                            color: th.textPrimary, // text-ink
                          ),
                        ),
                        const SizedBox(height: 6), // mt-1.5
                        Text(
                          request.description ??
                              (request.danger
                                  ? t.tr('confirmDialog.irreversible')
                                  : ''),
                          style: TextStyle(
                            fontSize: 14, // text-sm
                            height: 1.625, // leading-relaxed
                            color: th.textMuted, // text-muted
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Memory choices: strictly one at a time, none pre-ticked.
            Container(
              margin: const EdgeInsets.only(top: 16), // mt-4
              padding: const EdgeInsets.all(6), // p-1.5
              decoration: BoxDecoration(
                color: th.bgHover.withAlpha(153), // bg-hover/60
                borderRadius: BorderRadius.circular(8), // rounded-lg
              ),
              child: Column(
                children: [
                  _RememberRow(
                    label: t.tr('confirmDialog.rememberForever'),
                    checked: remember == ConfirmRemember.forever,
                    th: th,
                    onToggle: () =>
                        onToggleRemember(ConfirmRemember.forever),
                  ),
                  _RememberRow(
                    label: t.tr('confirmDialog.rememberHour'),
                    checked: remember == ConfirmRemember.hour,
                    th: th,
                    onToggle: () => onToggleRemember(ConfirmRemember.hour),
                  ),
                ],
              ),
            ),

            Container(
              margin: const EdgeInsets.only(top: 20), // mt-5
              padding: const EdgeInsets.only(top: 16), // pt-4
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0x1AFFFFFF)), // border-subtle
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TsundokuButton(
                    variant: ButtonVariant.secondary,
                    size: ButtonSize.lg,
                    onPressed: () => onChoose(false),
                    child: Text(
                        request.cancelLabel ?? t.tr('confirmDialog.cancel')),
                  ),
                  const SizedBox(width: 8), // gap-2
                  TsundokuButton(
                    variant: request.danger
                        ? ButtonVariant.danger
                        : ButtonVariant.primary,
                    size: ButtonSize.lg,
                    onPressed: () => onChoose(true),
                    child: Text(request.confirmLabel ??
                        t.tr('confirmDialog.confirm')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

/// Чекбокс «запомнить»: sr-only input + peer-checked квадрат с Check 11px.
class _RememberRow extends StatelessWidget {
  final String label;
  final bool checked;
  final TsundokuTheme th;
  final VoidCallback onToggle;

  const _RememberRow({
    required this.label,
    required this.checked,
    required this.th,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // px-2 py-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
          ),
          child: Row(
            children: [
              // Квадрат 16px: checked → accent bg/border + белый Check.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150), // duration-150
                width: 16, // size-4
                height: 16,
                decoration: BoxDecoration(
                  color: checked ? th.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(4), // rounded
                  border: Border.all(
                    color: checked ? th.accent : Colors.white.withAlpha(38),
                  ),
                ),
                child: checked
                    ? const Icon(LucideIcons.check,
                        size: 11, color: Colors.white)
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 10), // gap-2.5
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: th.textSecondary, // text-secondary
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
