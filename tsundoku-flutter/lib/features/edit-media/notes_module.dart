/// Порт `mediatracker-ui/src/features/edit-media/modules/NotesModule.svelte`.
///
/// Block 2 — standalone-редактор личных заметок. Один биндинг-стринг, без
/// API-вызовов: вызывающий решает, когда (и нужно ли) сохранить текст.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class NotesModule extends ConsumerStatefulWidget {
  /// Svelte `$bindable("")`: внутренний контроллер синхронизируется с
  /// внешним значением; правки отдаются через [onNotesChange].
  final String notes;
  final ValueChanged<String>? onNotesChange;
  final bool flat;
  final bool showLabel;

  const NotesModule({
    super.key,
    required this.notes,
    required this.onNotesChange,
    this.flat = false,
    this.showLabel = true,
  });

  @override
  ConsumerState<NotesModule> createState() => _NotesModuleState();
}

class _NotesModuleState extends ConsumerState<NotesModule> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.notes);
  }

  @override
  void didUpdateWidget(covariant NotesModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notes != oldWidget.notes && widget.notes != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.notes,
        selection: TextSelection.collapsed(offset: widget.notes.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return ModuleCard(
      flat: widget.flat,
      showLabel: widget.showLabel,
      title: t.tr('createModal.modules.notes'),
      count: null,
      icon: const Icon(LucideIcons.fileText, size: 15),
      // Flat-режим живёт в окне workspace (тело окна — Expanded, высота
      // ограничена хостом): растягивается на всю высоту (flex-1 Svelte).
      // В unbounded-контексте (standalone/скролл) — фикс ~min-h-[120px].
      child: LayoutBuilder(builder: (context, c) {
        final stretch = widget.flat && c.maxHeight.isFinite;
        return Container(
          height: stretch ? double.infinity : null,
          constraints:
              stretch ? null : const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(
                color: Colors.white.withAlpha(26)), // border-white/10
            color: th.bgSurface, // bg-field
          ),
          child: TextField(
            controller: _controller,
            onChanged: (value) => widget.onNotesChange?.call(value),
            expands: stretch,
            maxLines: stretch ? null : 5,
            minLines: stretch ? null : 5,
            keyboardType: TextInputType.multiline,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: th.textPrimary), // text-sm font-normal
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(12), // p-3
              border: InputBorder.none,
              hintText: t.tr('createModal.placeholders.notes'),
              hintStyle:
                  TextStyle(color: th.textMuted), // placeholder:text-muted
              isDense: true,
            ),
          ),
        );
      }),
    );
  }
}
