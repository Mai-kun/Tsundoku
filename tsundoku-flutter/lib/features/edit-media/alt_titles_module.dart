/// Порт
/// `mediatracker-ui/src/features/edit-media/modules/AltTitlesModule.svelte`.
///
/// Block 4 — альтернативные названия как читаемый список. Быстрый ввод сверху
/// разбивает вставленный текст по `/`, `,` и переводам строк, так что
/// `Название 1 / Название 2` ложится двумя элементами; каждый существующий
/// элемент — своя редактируемая строка (правка/удаление на месте). Списком
/// владеет вызывающий.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class AltTitlesModule extends ConsumerStatefulWidget {
  final bool flat;
  final bool showLabel;
  final List<String> altTitles;

  /// Svelte `altTitles = $bindable([])`.
  final ValueChanged<List<String>>? onChange;

  const AltTitlesModule({
    super.key,
    this.flat = false,
    this.showLabel = true,
    required this.altTitles,
    required this.onChange,
  });

  @override
  ConsumerState<AltTitlesModule> createState() => _AltTitlesModuleState();
}

class _AltTitlesModuleState extends ConsumerState<AltTitlesModule> {
  final TextEditingController _quickController = TextEditingController();
  int? _editingIndex;
  final TextEditingController _editingController = TextEditingController();

  void _commit(List<String> next) => widget.onChange?.call(next);

  /// Разбивка по `/`, `,` и newline + trim; дубликаты (case-insensitive)
  /// отфильтровываются — повторное добавление существующего тайтла — no-op.
  void _commitQuickInput() {
    final parts = _quickController.text
        .split(RegExp(r'[/,,\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    final existing =
        widget.altTitles.map((value) => value.toLowerCase()).toSet();
    final fresh = parts
        .where((value) => !existing.contains(value.toLowerCase()))
        .toList();
    if (fresh.isNotEmpty) _commit([...widget.altTitles, ...fresh]);
    _quickController.clear();
    setState(() {});
  }

  void _removeTitle(int index) {
    _commit(List<String>.from(widget.altTitles)..removeAt(index));
    if (_editingIndex == index) {
      setState(() {
        _editingIndex = null;
        _editingController.clear();
      });
    }
  }

  void _startEditing(int index) {
    setState(() {
      _editingIndex = index;
      _editingController.text = widget.altTitles[index];
    });
  }

  void _commitEditing() {
    if (_editingIndex == null) return;
    final trimmed = _editingController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.altTitles[_editingIndex!]) {
      final next = List<String>.from(widget.altTitles);
      next[_editingIndex!] = trimmed;
      _commit(next);
    }
    setState(() {
      _editingIndex = null;
      _editingController.clear();
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingIndex = null;
      _editingController.clear();
    });
  }

  @override
  void dispose() {
    _quickController.dispose();
    _editingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return ModuleCard(
      flat: widget.flat,
      showLabel: widget.showLabel,
      title: t.tr('createModal.modules.altTitles'),
      count: widget.altTitles.length,
      icon: const Icon(LucideIcons.tag, size: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Быстрый ввод + кнопка добавления (flex gap-2).
          Row(
            children: [
              Expanded(
                child: _AltInput(
                  controller: _quickController,
                  hint: t.tr('createModal.altTitlesModule.quickAddPlaceholder'),
                  onSubmitted: (_) => _commitQuickInput(),
                  onChanged: (_) => setState(() {}), // реактивная disabled-кнопка
                ),
              ),
              const SizedBox(width: 8), // gap-2
              GestureDetector(
                onTap: _quickController.text.trim().isEmpty
                    ? null
                    : _commitQuickInput,
                child: Container(
                  width: 36, // size-9
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                    color: _quickController.text.trim().isEmpty
                        ? th.accent.withAlpha(128) // disabled:opacity-50
                        : th.accent, // bg-accent
                  ),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.plus,
                      size: 16,
                      color: Colors.white), // text-white
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // space-y-3
          if (widget.altTitles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4), // px-1
              child: Text(
                t.tr('createModal.altTitlesModule.empty'),
                style: TextStyle(
                  fontSize: 14, // text-sm
                  color: th.textMuted,
                ),
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < widget.altTitles.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6), // space-y-1.5
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6), // px-2.5 py-1.5
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8), // rounded-lg
                        border: Border.all(
                            color: Colors.white
                                .withAlpha(15)), // border-white/[0.06]
                        color: Colors.white.withAlpha(8), // bg-white/[0.03]
                      ),
                      child: Row(
                        children: [
                          if (_editingIndex == index) ...[
                            Expanded(
                              child: _AltInput(
                                controller: _editingController,
                                autofocus: true,
                                focused: true,
                                // Enter → commit, Escape → cancel.
                                onSubmitted: (_) => _commitEditing(),
                                onEscape: _cancelEditing,
                                ariaLabel:
                                    t.tr('createModal.fields.altTitles'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SmallIconButton(
                              icon: LucideIcons.x,
                              size: 13,
                              semanticLabel: t.tr('common.cancel'),
                              onTap: _cancelEditing,
                            ),
                          ] else ...[
                            Expanded(
                              child: Text(
                                widget.altTitles[index],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14, // text-sm
                                  color: th.textPrimary, // text-ink
                                ),
                              ),
                            ),
                            _SmallIconButton(
                              icon: LucideIcons.pencil,
                              size: 13,
                              semanticLabel: t.tr('detailModal.edit'),
                              onTap: () => _startEditing(index),
                            ),
                            _SmallIconButton(
                              icon: LucideIcons.trash2,
                              size: 13,
                              semanticLabel: t.tr('common.delete'),
                              danger: true,
                              onTap: () => _removeTitle(index),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// h-9 rounded-lg border-white/10 bg-field px-3 text-sm (Svelte input).
class _AltInput extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final bool focused;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEscape;
  final String? ariaLabel;

  const _AltInput({
    required this.controller,
    required this.onSubmitted,
    this.hint,
    this.autofocus = false,
    this.focused = false,
    this.onChanged,
    this.onEscape,
    this.ariaLabel,
  });

  @override
  State<_AltInput> createState() => _AltInputState();
}

class _AltInputState extends State<_AltInput> {
  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return KeyboardListener(
      focusNode: FocusNode(skipTraversal: true),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onEscape?.call();
        }
      },
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autofocus,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        style: TextStyle(
          fontSize: 14, // text-sm
          fontWeight: FontWeight.w400,
          color: th.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: widget.focused ? th.bgSurface : th.bgSurface, // bg-field
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // h-9
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: widget.focused
                  ? th.accent.withAlpha(153)
                  : Colors.white.withAlpha(26),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: widget.focused
                  ? th.accent.withAlpha(153) // border-indigo-500/60
                  : Colors.white.withAlpha(26),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: th.accent.withAlpha(153)),
          ),
          hintText: widget.hint,
          hintStyle: TextStyle(color: th.textMuted),
        ),
      ),
    );
  }
}

/// size-6 rounded-md icon-кнопки строк (edit/delete/cancel).
class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool danger;

  const _SmallIconButton({
    required this.icon,
    required this.size,
    required this.semanticLabel,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24, // size-6
          height: 24,
          decoration:
              BoxDecoration(borderRadius: BorderRadius.circular(6)), // rounded-md
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: size,
            // hover: delete → rose-300, edit/cancel → text-ink (hover — stateful
            // opacity в Svelte через group-hover; в Flutter кнопки всегда
            // видимы, rose-оттенок сохранён).
            color: danger ? th.textMuted : th.textMuted,
          ),
        ),
      ),
    );
  }
}
