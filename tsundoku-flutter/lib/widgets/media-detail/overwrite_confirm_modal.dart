/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/OverwriteConfirmModal.svelte`.
///
/// Диалог конфликта перезаписи: safe (только пустые поля) / full overwrite /
/// отмена.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/ui/modal.dart';

/// Диалог перезаписи (1-в-1 с OverwriteConfirmModal.svelte).
class OverwriteConfirmModal extends ConsumerWidget {
  final bool isOpen;
  final bool busy;

  /// Заполняет пропуски; правки пользователя сохраняются.
  final VoidCallback onFillMissing;

  /// Полная перезапись; правки пользователя теряются.
  final VoidCallback onOverwrite;
  final VoidCallback onClose;

  const OverwriteConfirmModal({
    super.key,
    required this.isOpen,
    required this.busy,
    required this.onFillMissing,
    required this.onOverwrite,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return TsundokuModal(
      isOpen: isOpen,
      onClose: onClose,
      size: ModalSize.md,
      contentPadding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20), // p-5
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tr('detail.overwriteTitle'),
                  style: const TextStyle(
                    fontSize: 16, // text-base
                    fontWeight: FontWeight.w600, // font-semibold
                    color: Colors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6), // mt-1.5
                  child: Text(
                    t.tr('detail.overwriteHint'),
                    style: TextStyle(
                      fontSize: 14, // text-sm
                      color: th.textMuted, // text-muted
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Кнопки (border-t white/[0.08]).
          Container(
            padding: const EdgeInsets.all(20), // p-5
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
            ),
            child: Column(
              children: [
                // Safe: bg-accent, hover accent-hover.
                _OverwriteButton(
                  label: t.tr('detail.overwriteSafe'),
                  busy: busy,
                  background: th.accent, // bg-accent
                  foreground: Colors.white,
                  onTap: onFillMissing,
                ),
                const SizedBox(height: 8), // gap-2
                // Full overwrite: text-muted + hover rose.
                _OverwriteFullButton(
                  label: t.tr('detail.overwriteFull'),
                  busy: busy,
                  th: th,
                  onTap: onOverwrite,
                ),
                // Отмена.
                Padding(
                  padding: const EdgeInsets.only(top: 4), // mt-1
                  child: _OverwriteCancelButton(
                    label: t.tr('common.cancel'),
                    busy: busy,
                    th: th,
                    onTap: onClose,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary-кнопка: bg-accent hover accent-hover, disabled:opacity-60.
class _OverwriteButton extends StatefulWidget {
  final String label;
  final bool busy;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _OverwriteButton({
    required this.label,
    required this.busy,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  State<_OverwriteButton> createState() => _OverwriteButtonState();
}

class _OverwriteButtonState extends State<_OverwriteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
      onTap: widget.busy ? null : widget.onTap,
      child: Container(
        width: double.infinity, // w-full
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // px-4 py-2.5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), // rounded-lg
          color: widget.busy
              ? widget.background.withAlpha(153) // disabled:opacity-60
              : _hovered
                  ? th.accentHover // hover:bg-accent-hover
                  : widget.background,
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14, // text-sm
            fontWeight: FontWeight.w500, // font-medium
            color: widget.foreground,
          ),
        ),
      ),
      ),
    );
  }
}

/// Полная перезапись: border-white/10, hover rose.
class _OverwriteFullButton extends StatefulWidget {
  final String label;
  final bool busy;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _OverwriteFullButton({
    required this.label,
    required this.busy,
    required this.th,
    required this.onTap,
  });

  @override
  State<_OverwriteFullButton> createState() => _OverwriteFullButtonState();
}

class _OverwriteFullButtonState extends State<_OverwriteFullButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
      onTap: widget.busy ? null : widget.onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // px-4 py-2.5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), // rounded-lg
          border: Border.all(
            color: _hovered
                ? const Color(0x66F87171) // hover:border-rose-400/40
                : Colors.white.withAlpha(26), // border-white/10
          ),
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14, // text-sm
            fontWeight: FontWeight.w500, // font-medium
            color: _hovered
                ? const Color(0xFFFECDD3) // hover:text-rose-200
                : th.textMuted, // text-muted
          ),
        ),
      ),
      ),
    );
  }
}

/// Кнопка отмены: text-muted, hover:text-white, disabled:opacity-60.
class _OverwriteCancelButton extends StatefulWidget {
  final String label;
  final bool busy;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _OverwriteCancelButton({
    required this.label,
    required this.busy,
    required this.th,
    required this.onTap,
  });

  @override
  State<_OverwriteCancelButton> createState() => _OverwriteCancelButtonState();
}

class _OverwriteCancelButtonState extends State<_OverwriteCancelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onTap,
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // px-4 py-2
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 14, // text-sm
                color: widget.busy
                    ? widget.th.textMuted.withAlpha(153) // disabled:opacity-60
                    : _hovered
                        ? Colors.white // hover:text-white
                        : widget.th.textMuted, // text-muted
              ),
            ),
          ),
        ),
      ),
    );
  }
}
