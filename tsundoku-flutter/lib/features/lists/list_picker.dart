/// 1:1 port of `mediatracker-ui/src/features/lists/ListPicker.svelte`.
///
/// Модалка «добавить в списки»: чек-лист CustomListSummary (цвет, имя,
/// itemsCount), оптимистичный toggle add/remove с откатом, loading/empty.
/// CreateListModal (Фаза 5) грузится лениво по кнопке «+ Новый список» —
/// в Dart это колбек [onCreateList], который App подключит, когда модалка
/// будет портирована (решение #38).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/dtos.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/toast.dart';

class ListPicker extends ConsumerStatefulWidget {
  final String mediaId;
  final bool isOpen;
  final VoidCallback? onClose;

  /// Динамический import CreateListModal → колбек (App композиция, Фаза 5).
  final VoidCallback? onCreateList;

  /// Кнопка-триггер «В списки» рендерится только когда onClose не передан
  /// (1-в-1 с `{#if !onClose}` в Svelte: standalone-режим).
  final bool showTrigger;

  const ListPicker({
    super.key,
    required this.mediaId,
    this.isOpen = false,
    this.onClose,
    this.onCreateList,
    this.showTrigger = true,
  });

  @override
  ConsumerState<ListPicker> createState() => ListPickerState();
}

class ListPickerState extends ConsumerState<ListPicker> {
  bool _open = false;
  bool _loading = false;
  List<CustomListSummary> _lists = const <CustomListSummary>[];
  List<String> _included = const <String>[];
  List<String> _busyIds = const <String>[];

  @override
  void initState() {
    super.initState();
    // $effect: isOpen → showPicker.
    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showPicker());
      });
    }
  }

  @override
  void didUpdateWidget(ListPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      unawaited(_showPicker());
    }
  }

  void _handleClose() {
    setState(() => _open = false);
    widget.onClose?.call();
  }

  Future<void> _showPicker() async {
    setState(() {
      _open = true;
      _loading = true;
    });
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    final api = ref.read(apiClientProvider);
    try {
      final results =
          await Future.wait([api.getLists(), api.getListsForMedia(widget.mediaId)]);
      if (!mounted) return;
      setState(() {
        _lists = results[0] as List<CustomListSummary>;
        _included = results[1] as List<String>;
      });
    } catch (error) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(CustomListSummary list) async {
    if (_busyIds.contains(list.id)) return;
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    final api = ref.read(apiClientProvider);

    final wasIncluded = _included.contains(list.id);
    setState(() {
      _included = wasIncluded
          ? _included.where((id) => id != list.id).toList()
          : [..._included, list.id];
      _busyIds = [..._busyIds, list.id];
    });
    try {
      if (wasIncluded) {
        await api.removeMediaFromList(list.id, widget.mediaId);
      } else {
        await api.addMediaToList(list.id, widget.mediaId);
      }
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: wasIncluded
              ? t.tf('views.listRemoved', [list.name])
              : t.tf('views.listAdded', [list.name]),
          description: t.tr('toast.descCreated'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _included = wasIncluded
            ? [..._included, list.id]
            : _included.where((id) => id != list.id).toList();
      });
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyIds = _busyIds.where((id) => id != list.id).toList();
        });
      }
    }
  }

  /// Обновление списка после сохранения CreateListModal (App подключит
  /// onSaved → refreshLists при портировании модалки, Фаза 5).
  Future<void> refreshLists() async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      final lists = await ref.read(apiClientProvider).getLists();
      if (!mounted) return;
      setState(() => _lists = lists);
    } catch (error) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    final modal = TsundokuModal(
      isOpen: _open,
      onClose: _handleClose,
      size: ModalSize.md,
      contentPadding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24), // p-5 sm:p-6 — md-модалка узкая, p-5
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.tr('views.listPickerTitle'),
                    style: TextStyle(
                      fontSize: 18, // text-lg
                      fontWeight: FontWeight.w700, // font-bold
                      color: th.textPrimary, // text-ink
                    ),
                  ),
                ),
                _CreateListButton(
                  label: t.tr('views.listNew'),
                  th: th,
                  onPressed: widget.onCreateList,
                ),
              ],
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32), // py-8
                child: Text(
                  t.tr('common.loading'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    color: th.textMuted, // text-muted
                  ),
                ),
              )
            else if (_lists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32), // py-8
                child: Text(
                  t.tr('views.listPickerEmpty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: th.textMuted,
                  ),
                ),
              )
            else
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(top: 16), // mt-4
                  constraints: const BoxConstraints(
                      maxHeight: 360), // max-h-[60vh] @ 900px
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final list in _lists)
                          _ListRow(
                            list: list,
                            included: _included.contains(list.id),
                            busy: _busyIds.contains(list.id),
                            th: th,
                            t: t,
                            onToggle: () => unawaited(_toggle(list)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Standalone-режим: без onClose рендерится кнопка-триггер (1-в-1).
    if (!widget.showTrigger || widget.onClose != null) {
      return modal;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TriggerButton(
          label: t.tr('views.listAddTo'),
          th: th,
          onPressed: () => unawaited(_showPicker()),
        ),
        modal,
      ],
    );
  }
}

/// Триггер «В списки»: bg-surface/50 rounded-lg px-3 py-2.5 text-xs
/// font-medium, иконка accent-soft.
class _TriggerButton extends StatelessWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onPressed;

  const _TriggerButton({
    required this.label,
    required this.th,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // px-3 py-2.5
          decoration: BoxDecoration(
            color: th.bgSurface.withAlpha(128), // bg-surface/50
            borderRadius: BorderRadius.circular(8), // rounded-lg
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.list, // List size={15}
                size: 15,
                color: th.accentSoft, // --color-accent-soft
              ),
              const SizedBox(width: 10), // gap-2.5
              Text(
                label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: th.textMuted, // ink-dim ≈ muted
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка «+ Новый список»: text-accent-soft px-2.5 py-1.5 text-xs
/// font-semibold hover:bg-white/5.
class _CreateListButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback? onPressed;

  const _CreateListButton({
    required this.label,
    required this.th,
    required this.onPressed,
  });

  @override
  State<_CreateListButton> createState() => _CreateListButtonState();
}

class _CreateListButtonState extends State<_CreateListButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6), // px-2.5 py-1.5
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withAlpha(13) : Colors.transparent,
            borderRadius: BorderRadius.circular(8), // rounded-lg
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.plus, // Plus size={14}
                size: 14,
                color: widget.th.accentSoft, // text-accent-soft
              ),
              const SizedBox(width: 6), // gap-1.5
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: widget.th.accentSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка списка: чекбокс 16px + цветной квадрат 32px с List-иконкой +
/// имя + titlesCount.
class _ListRow extends StatelessWidget {
  final CustomListSummary list;
  final bool included;
  final bool busy;
  final TsundokuTheme th;
  final I18nDictionary t;
  final VoidCallback onToggle;

  const _ListRow({
    required this.list,
    required this.included,
    required this.busy,
    required this.th,
    required this.t,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: busy ? null : onToggle,
        child: Opacity(
          opacity: busy ? 0.6 : 1,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12), // px-3 py-3
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
            ),
            child: Row(
              children: [
                // accent-indigo-500 чекбокс.
                Container(
                  width: 16, // h-4 w-4
                  height: 16,
                  decoration: BoxDecoration(
                    color: included ? const Color(0xFF6366F1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: included
                          ? const Color(0xFF6366F1)
                          : Colors.white.withAlpha(77),
                    ),
                  ),
                  child: included
                      ? const Icon(LucideIcons.check,
                          size: 11, color: Colors.white)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 12), // gap-3
                Container(
                  width: 32, // h-8 w-8
                  height: 32,
                  decoration: BoxDecoration(
                    // background: list.color ?? var(--color-accent)
                    color: _parseColor(list.color) ?? th.accent,
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                  ),
                  child: const Icon(LucideIcons.list, size: 15, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    list.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis, // truncate
                    style: TextStyle(
                      fontSize: 14, // text-sm
                      fontWeight: FontWeight.w500, // font-medium
                      color: th.textPrimary, // text-ink
                    ),
                  ),
                ),
                Text(
                  t.tf('views.listTitles', [list.itemsCount]),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: th.textMuted, // text-muted
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `style="background:${list.color}"` — hex-строка сервера (#rrggbb).
  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}
