/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/MediaActivityModal.svelte`.
///
/// История активности тайтла: дата-фильтр (showDatePicker), лента событий
/// (иконки по типу, время/дата), optimistic delete через confirmDialog.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/confirm_dialog.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/toast.dart';
import '../../shared/utils/history_formatters.dart';

/// Модалка истории активности (1-в-1 с MediaActivityModal.svelte).
class MediaActivityModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final String mediaId;
  final String title;
  final VoidCallback onClose;

  const MediaActivityModal({
    super.key,
    required this.isOpen,
    required this.mediaId,
    required this.title,
    required this.onClose,
  });

  @override
  ConsumerState<MediaActivityModal> createState() => _MediaActivityModalState();
}

class _MediaActivityModalState extends ConsumerState<MediaActivityModal> {
  String _selectedDate = '';
  List<HistoryEvent> _events = <HistoryEvent>[];
  bool _loading = false;
  Object? _loadError;
  String? _deletingId;
  int _requestSequence = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isOpen && widget.mediaId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEvents(++_requestSequence);
      });
    }
  }

  @override
  void didUpdateWidget(covariant MediaActivityModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect-аналог: открытие/mediaId → загрузка.
    if (widget.isOpen && widget.mediaId.isNotEmpty && !oldWidget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEvents(++_requestSequence);
      });
    }
  }

  Future<void> _loadEvents(int sequence) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final nextEvents = await ref
          .read(apiClientProvider)
          .getHistoryEvents(
              mediaId: widget.mediaId,
              date: _selectedDate.isNotEmpty ? _selectedDate : null);
      if (sequence == _requestSequence && mounted) {
        setState(() => _events = nextEvents);
      }
    } catch (error) {
      if (sequence == _requestSequence && mounted) {
        setState(() => _loadError = error);
      }
    } finally {
      if (sequence == _requestSequence && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _retry() {
    _loadEvents(++_requestSequence);
  }

  Future<void> _handleDeleteEvent(HistoryEvent event) async {
    if (_deletingId != null) return;
    final t = ref.read(tProvider);
    if (!(await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-history-entry',
        title: t.tr('views.confirmDeleteHistoryEntry'),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    ))) {
      return;
    }

    final prevEvents = List<HistoryEvent>.from(_events);
    setState(() {
      _deletingId = event.id;
      _events = _events.where((x) => x.id != event.id).toList();
    });
    final locale = ref.read(i18nProvider);
    try {
      await ref.read(apiClientProvider).deleteHistoryEvent(event.id);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('views.historyEntryDeleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _events = prevEvents);
      _errorToast(error, locale);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _errorToast(Object error, Locale locale) {
    final t = ref.read(tProvider);
    showToast(
      ref,
      ToastOptions(
        title: t.tr('toast.actionFailed'),
        description: errorMessage(error, locale),
        type: ToastType.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: widget.onClose,
      size: ModalSize.md,
      contentPadding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75, // max-h-[75vh]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16), // px-5 py-4
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.history,
                      size: 18, color: th.accentSoft), // accent-soft
                  const SizedBox(width: 12), // gap-3
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.tr('views.historyTitle'),
                          style: const TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w700, // font-bold
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12, // text-xs
                            color: th.textMuted, // text-muted
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ActivityCloseButton(
                    label: t.tr('common.close'),
                    th: th,
                    onClose: widget.onClose,
                  ),
                ],
              ),
            ),
            // Дата-фильтр.
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12), // px-5 py-3
              decoration: BoxDecoration(
                color: th.bgSurface.withAlpha(77), // bg-surface/30
                border: const Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
              ),
            child: Row(
              children: [
                Text(
                  '${t.tr('views.filterByDate')}:',
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: th.textMuted, // text-muted
                  ),
                ),
                const SizedBox(width: 8), // gap-2
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate.isNotEmpty
                          ? DateTime.parse(_selectedDate)
                          : DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = DateFormat('yyyy-MM-dd').format(picked);
                      });
                      _loadEvents(++_requestSequence);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6), // px-3 py-1.5
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8), // rounded-lg
                      border: Border.all(
                          color: Colors.white.withAlpha(26)), // white/10
                      color: th.bgSurface, // bg-field
                    ),
                    child: Text(
                      _selectedDate.isEmpty
                          ? '—'
                          : _selectedDate,
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (_selectedDate.isNotEmpty) ...[
                  const SizedBox(width: 8), // gap-2
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedDate = '');
                      _loadEvents(++_requestSequence);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6), // px-2.5 py-1.5
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withAlpha(26)),
                        color: th.bgSurface, // bg-field
                      ),
                      child: Text(
                        t.tr('views.resetDate'),
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted, // text-muted
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Лента активности.
          Flexible(
            child: Container(
              constraints: const BoxConstraints(minHeight: 220), // min-h-[220px]
              padding: const EdgeInsets.all(20), // p-5
              child: _loading
                  ? Column(
                      children: [
                        for (var index = 0; index < 3; index++)
                          Container(
                            width: double.infinity,
                            height: 56, // h-14
                            margin:
                                const EdgeInsets.only(bottom: 12), // space-y-3
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: th.bgCard, // bg-card
                            ),
                          ),
                      ],
                    )
                  : _loadError != null
                      ? Container(
                          padding: const EdgeInsets.all(24), // p-6
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0x0DF87171), // rose-400/5
                          ),
                          child: Column(
                            children: [
                              Text(
                                errorMessage(_loadError!, locale),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14, // text-sm
                                  color: Color(0xFFFECDD3), // text-rose-200
                                ),
                              ),
                              const SizedBox(height: 12), // gap-3
                              _RetryActivityButton(
                                label: t.tr('common.retry'),
                                th: th,
                                onTap: _retry,
                              ),
                            ],
                          ),
                        )
                      : _events.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(24), // p-6
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: th.bgSurface
                                    .withAlpha(128), // bg-surface/50
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 40, // h-10 w-10
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(8), // rounded-lg
                                      color: th.bgCard, // bg-card
                                    ),
                                    child: Icon(LucideIcons.history,
                                        size: 20, color: th.textMuted),
                                  ),
                                  const SizedBox(height: 12), // gap-3
                                  Text(
                                    _selectedDate.isNotEmpty
                                        ? t.tr('views.noActivityForDate')
                                        : t.tr('views.noActivity'),
                                    style: TextStyle(
                                      fontSize: 12, // text-xs
                                      color: th.textMuted, // text-muted
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (final event in _events)
                                    _ActivityRow(
                                      event: event,
                                      th: th,
                                      t: t,
                                      locale: locale,
                                      busy: _deletingId != null,
                                      deleting:
                                          _deletingId == event.id,
                                      deleteLabel: t
                                          .tr('views.confirmDeleteHistoryEntry'),
                                      onDelete: () => _handleDeleteEvent(event),
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
  }
}

/// Строка события: иконка по типу + label + время/дата + hover-delete.
class _ActivityRow extends StatelessWidget {
  final HistoryEvent event;
  final TsundokuTheme th;
  final I18nDictionary t;
  final Locale locale;
  final bool busy;
  final bool deleting;
  final String deleteLabel;
  final VoidCallback onDelete;

  const _ActivityRow({
    required this.event,
    required this.th,
    required this.t,
    required this.locale,
    required this.busy,
    required this.deleting,
    required this.deleteLabel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final icon = historyEventIcons[event.type] ?? LucideIcons.history;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), // space-y-2.5
      padding: const EdgeInsets.all(12), // p-3
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
        color: th.bgCard.withAlpha(153), // bg-card/60
      ),
      child: Row(
        children: [
          Container(
            width: 36, // h-9 w-9
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              color: th.accent.withAlpha(38), // bg-accent/15
            ),
            child: Icon(icon, size: 16, color: th.accentSoft), // accent-soft
          ),
          const SizedBox(width: 14), // gap-3.5
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatHistoryEventLabel(event, t),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    color: th.textPrimary, // text-ink
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2), // mt-0.5
                  child: Row(
                    children: [
                      Text(
                        formatHistoryTime(event.createdAt, locale),
                        style: TextStyle(
                          fontSize: 11, // text-[11px]
                          fontWeight: FontWeight.w500, // font-medium
                          color: Colors.white.withAlpha(204), // white/80
                        ),
                      ),
                      const SizedBox(width: 6), // gap-1.5
                      Text('·', style: TextStyle(color: th.textMuted)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          formatHistoryDate(event.createdAt, locale),
                          style: TextStyle(
                            fontSize: 11,
                            color: th.textMuted, // text-muted
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Delete: hover-видимость в Svelte; во Flutter — всегда видима
          // (hover-стейт в строках журнала громоздок, a11y-приоритет).
          GestureDetector(
            onTap: busy ? null : onDelete,
            child: Container(
              width: 28, // h-7 w-7
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // rounded-md
                color: Colors.transparent,
              ),
              child: deleting
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF94A3B8)),
                    )
                  : Icon(LucideIcons.trash2,
                      size: 13,
                      color: busy
                          ? Colors.white.withAlpha(102) // disabled:opacity-40
                          : th.textMuted), // text-muted
            ),
          ),
        ],
      ),
    );
  }
}

/// Retry-кнопка error-блока: bg-accent.
class _RetryActivityButton extends StatelessWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _RetryActivityButton({
    required this.label,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // px-4 py-2
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6), // rounded-md
          color: th.accent, // bg-accent
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.refreshCw,
                size: 14, color: Colors.white),
            const SizedBox(width: 8), // gap-2
            Text(
              label,
              style: const TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w500, // font-medium
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// X-кнопка закрытия: hover bg-white/5.
class _ActivityCloseButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onClose;

  const _ActivityCloseButton({
    required this.label,
    required this.th,
    required this.onClose,
  });

  @override
  State<_ActivityCloseButton> createState() => _ActivityCloseButtonState();
}

class _ActivityCloseButtonState extends State<_ActivityCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label, // aria-label
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            padding: const EdgeInsets.all(6), // p-1.5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              color: _hovered
                  ? Colors.white.withAlpha(13) // hover:bg-white/5
                  : Colors.transparent,
            ),
            child: Icon(
              LucideIcons.x,
              size: 16,
              color: _hovered
                  ? Colors.white // hover:text-white
                  : widget.th.textMuted, // text-muted
            ),
          ),
        ),
      ),
    );
  }
}
