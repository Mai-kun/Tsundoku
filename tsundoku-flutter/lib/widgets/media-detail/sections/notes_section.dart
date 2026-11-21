/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/NotesSection.svelte`.
///
/// Заметки тайтла: панель с текстом (whitespace-pre-line) + Edit, либо
/// пустая dashed-кнопка-приглашение.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';

/// Секция заметок (1-в-1 с NotesSection.svelte).
class NotesSection extends ConsumerStatefulWidget {
  final String? notes;
  final VoidCallback onEdit;

  const NotesSection({
    super.key,
    required this.notes,
    required this.onEdit,
  });

  @override
  ConsumerState<NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends ConsumerState<NotesSection> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    final hasNotes = widget.notes?.trim().isNotEmpty ?? false;
    final title = t.tr('detail.yourNotes');
    final placeholder = t.tr('detail.notesPlaceholder');

    if (hasNotes) {
      return Container(
        padding: const EdgeInsets.all(20), // p-5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(color: Colors.white.withAlpha(15)),
          color: th.bgSurface, // panel-line
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(LucideIcons.bookOpen,
                          size: 16, color: th.textMuted), // text-muted
                      const SizedBox(width: 8), // gap-2
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w600, // font-semibold
                            color: th.textPrimary, // text-ink
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _EditNotesButton(label: t.tr('detailModal.edit'), onTap: widget.onEdit),
              ],
            ),
            const SizedBox(height: 8), // space-y-2
            Text(
              widget.notes!,
              style: TextStyle(
                fontSize: 14, // text-sm
                height: 1.625, // leading-relaxed
                color: th.textSecondary, // text-[var(--color-ink-dim)]
              ),
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          constraints: const BoxConstraints(minHeight: 140), // min-h-[140px]
          padding: const EdgeInsets.all(20), // p-5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(
              color: _hovered
                  ? Colors.white.withAlpha(51) // hover:border-white/20
                  : Colors.white.withAlpha(26), // border-white/10 (dashed ⏭️)
            ),
            color: _hovered
                ? Colors.white.withAlpha(8) // hover:bg-white/[0.03]
                : th.bgSurface.withAlpha(128), // panel-line/50
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, // size-10
                height: 40,
                margin: const EdgeInsets.only(bottom: 12), // mb-3
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12), // rounded-xl
                  color: Colors.white.withAlpha(13), // bg-white/[0.05]
                ),
                child: Icon(
                  LucideIcons.pencil,
                  size: 18,
                  color: _hovered ? th.textPrimary : th.textMuted,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14, // text-sm
                  fontWeight: FontWeight.w600, // font-semibold
                  color: th.textPrimary, // text-ink
                ),
              ),
              const SizedBox(height: 8), // mt-2
              Text(
                placeholder,
                style: TextStyle(
                  fontSize: 14, // text-sm
                  height: 1.625, // leading-relaxed
                  color: th.textMuted.withAlpha(204), // text-muted/80
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка Edit внутри панели: px-2.5 py-1.5 text-xs + Pencil.
class _EditNotesButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _EditNotesButton({required this.label, required this.onTap});

  @override
  State<_EditNotesButton> createState() => _EditNotesButtonState();
}

class _EditNotesButtonState extends State<_EditNotesButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6), // px-2.5 py-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            color: _hovered
                ? Colors.white.withAlpha(13) // hover:bg-white/[0.05]
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.pencil,
                  size: 13,
                  color: _hovered
                      ? th.textPrimary // hover:text-ink
                      : th.textMuted),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: _hovered ? th.textPrimary : th.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
