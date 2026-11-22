/// 1:1 port of `mediatracker-ui/src/features/stale-triage/StaleBacklogModal.svelte`.
///
/// Модалка ревизии заброшенного бэклога: фильтрация тайтлов «В процессе» по
/// порогам неактивности (90, 180, 365 дней), быстрые действия в 1 клик
/// (В фокус, На паузу, Бросить с открытием DropReasonModal, В планы),
/// оптимистичное удаление из списка ревизии и тосты обратной связи.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/media_labels.dart';
import '../../entities/media/model/stale_triage.dart';
import '../../features/drop-reason/drop_reason_prompt.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/toast.dart';

class StaleBacklogModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final List<MediaItem>? items;
  final VoidCallback? onMediaChanged;

  const StaleBacklogModal({
    super.key,
    required this.isOpen,
    required this.onClose,
    this.items,
    this.onMediaChanged,
  });

  @override
  ConsumerState<StaleBacklogModal> createState() => _StaleBacklogModalState();
}

class _StaleBacklogModalState extends ConsumerState<StaleBacklogModal> {
  int _threshold = 180;
  List<MediaItem> _allInProgress = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isOpen) {
      _initData();
    }
  }

  @override
  void didUpdateWidget(StaleBacklogModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isOpen && widget.isOpen) {
      _initData();
    }
  }

  void _initData() {
    if (widget.items != null) {
      setState(() => _allInProgress = List.from(widget.items!));
      return;
    }

    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    final locale = ref.read(i18nProvider);
    final t = ref.read(tProvider);

    api
        .getMedia(const MediaFilters(status: MediaStatus.inProgress))
        .then((res) {
      if (mounted) {
        setState(() {
          _allInProgress = res;
          _loading = false;
        });
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: errorMessage(e, locale),
            type: ToastType.error,
          ),
        );
      }
    });
  }

  List<MediaItem> get _staleItems {
    return _allInProgress
        .where((item) => isStaleInProgress(item, thresholdDays: _threshold))
        .toList();
  }

  String _formatProgress(MediaItem item, I18nDictionary t) {
    if (item.type == MediaType.tvshow) {
      final cur = item.totalEpisodesWatched ?? 0;
      final tot = item.totalEpisodesCount ?? 0;
      final pct = tot > 0 ? ' (${((cur / tot) * 100).round()}%)' : '';
      return '${t.tf('card.episodes', [cur, tot])}$pct';
    }
    if (item.type == MediaType.book) {
      final cur = item.currentPage ?? 0;
      final tot = item.totalPages ?? 0;
      final pct = tot > 0 ? ' (${((cur / tot) * 100).round()}%)' : '';
      return '${t.tf('card.pages', [cur, tot])}$pct';
    }
    if (item.type == MediaType.manga) {
      final cur = item.currentChapter ?? 0;
      final tot = item.totalChapters ?? 0;
      final pct = tot > 0 ? ' (${((cur / tot) * 100).round()}%)' : '';
      return '${t.tf('card.chapters', [cur, tot])}$pct';
    }
    if (item.type == MediaType.game) {
      return t.tf('card.hours', [item.hoursPlayed ?? 0]);
    }
    if (item.type == MediaType.movie) {
      return item.durationMinutes != null
          ? t.tf('card.movie', [item.durationMinutes!])
          : '';
    }
    return '';
  }

  String _formatDate(String? rawDate, Locale locale) {
    if (rawDate == null || rawDate.isEmpty) return '—';
    try {
      final d = DateTime.parse(rawDate).toLocal();
      const monthsRu = [
        'янв.',
        'февр.',
        'марта',
        'апр.',
        'мая',
        'июня',
        'июля',
        'авг.',
        'сент.',
        'окт.',
        'нояб.',
        'дек.'
      ];
      const monthsEn = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final isRu = locale == Locale.ru;
      final month = isRu ? monthsRu[d.month - 1] : monthsEn[d.month - 1];
      return '${d.day} $month ${d.year}';
    } catch (_) {
      return '—';
    }
  }

  Future<void> _handleFocus(MediaItem item) async {
    setState(() {
      _allInProgress = _allInProgress.where((x) => x.id != item.id).toList();
    });

    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    showToast(
      ref,
      ToastOptions(
        title: t.tr('staleTriage.toastFocus'),
        description: t.tr('toast.descUpdated'),
      ),
    );

    try {
      final api = ref.read(apiClientProvider);
      await api.updateMedia(
        item.id,
        UpdateMediaPayload(
          lastActivityAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      widget.onMediaChanged?.call();
    } catch (e) {
      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: errorMessage(e, locale),
            type: ToastType.error,
          ),
        );
      }
    }
  }

  Future<void> _handlePause(MediaItem item) async {
    setState(() {
      _allInProgress = _allInProgress.where((x) => x.id != item.id).toList();
    });

    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    showToast(
      ref,
      ToastOptions(
        title: t.tr('staleTriage.toastOnHold'),
        description: t.tr('toast.descUpdated'),
      ),
    );

    try {
      final api = ref.read(apiClientProvider);
      await api.updateStatus(item.id, MediaStatus.onHold);
      widget.onMediaChanged?.call();
    } catch (e) {
      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: errorMessage(e, locale),
            type: ToastType.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDrop(MediaItem item) async {
    setState(() {
      _allInProgress = _allInProgress.where((x) => x.id != item.id).toList();
    });

    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    showToast(
      ref,
      ToastOptions(
        title: t.tr('staleTriage.toastDropped'),
        description: t.tr('toast.descUpdated'),
      ),
    );

    try {
      final api = ref.read(apiClientProvider);
      await api.updateStatus(item.id, MediaStatus.dropped);
      widget.onMediaChanged?.call();

      ref.read(dropPromptStateProvider.notifier).open(
            DropPromptTarget(
              id: item.id,
              title: item.title,
              type: item.type.name,
              isAnime: item.isAnime,
              dropReason: item.dropReason,
              dropNotes: item.dropNotes,
              onSaved: (_, _) => widget.onMediaChanged?.call(),
            ),
          );
    } catch (e) {
      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: errorMessage(e, locale),
            type: ToastType.error,
          ),
        );
      }
    }
  }

  Future<void> _handleToPlanned(MediaItem item) async {
    setState(() {
      _allInProgress = _allInProgress.where((x) => x.id != item.id).toList();
    });

    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    showToast(
      ref,
      ToastOptions(
        title: t.tr('staleTriage.toastPlanned'),
        description: t.tr('toast.descUpdated'),
      ),
    );

    try {
      final api = ref.read(apiClientProvider);
      await api.updateStatus(item.id, MediaStatus.planned);
      widget.onMediaChanged?.call();
    } catch (e) {
      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: errorMessage(e, locale),
            type: ToastType.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final stale = _staleItems;

    final thresholdOptions = [
      (90, t.tr('staleTriage.threshold90')),
      (180, t.tr('staleTriage.threshold180')),
      (365, t.tr('staleTriage.threshold365')),
    ];

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: widget.onClose,
      size: ModalSize.lg,
      contentPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0x0DFFFFFF)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0x1AF59E0B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x33F59E0B)),
                  ),
                  child: const Icon(
                    LucideIcons.hourglass,
                    size: 20,
                    color: Color(0xFFFBBF24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('staleTriage.staleTriageTitle'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.tr('staleTriage.staleTriageSubtitle'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.x,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Threshold selector bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0x05FFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0x0DFFFFFF)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: thresholdOptions.map((opt) {
                        final isSelected = _threshold == opt.$1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: InkWell(
                            onTap: () => setState(() => _threshold = opt.$1),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF8B5CF6)
                                    : const Color(0x0DFFFFFF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                opt.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.tf('staleTriage.foundCount', [stale.length]),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          // Items list or success state
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(t, locale, stale),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    I18nDictionary t,
    Locale locale,
    List<MediaItem> stale,
  ) {
    if (_loading) {
      return Center(
        child: Text(
          t.tr('common.loading'),
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
      );
    }

    if (stale.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0x1A10B981),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x3310B981)),
              ),
              child: const Center(
                child: Text('🎉', style: TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.tr('staleTriage.triageCompleteTitle'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                t.tf('staleTriage.triageCompleteText', [_threshold]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: stale.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = stale[index];
        final rawDate =
            item.lastActivityAt ?? item.startedAt ?? item.createdAt;
        final days = getDaysInactive(
          lastActivityAt: item.lastActivityAt,
          startedAt: item.startedAt,
          createdAt: item.createdAt,
        );
        final progress = _formatProgress(item, t);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x05FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x0DFFFFFF)),
          ),
          child: Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 56,
                  height: 84,
                  color: const Color(0x0DFFFFFF),
                  child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                      ? Image.network(
                          item.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              LucideIcons.image,
                              size: 20,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            LucideIcons.image,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x0DFFFFFF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x1AFFFFFF)),
                          ),
                          child: Text(
                            cardTypeLabel(item, t),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (progress.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        progress,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      t.tf('staleTriage.daysInactive',
                          [days, _formatDate(rawDate, locale)]),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFFBBF24),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Action buttons (Focus, Pause, Drop, ToPlanned)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionButton(
                      icon: LucideIcons.flame,
                      label: t.tr('staleTriage.actionFocus'),
                      color: const Color(0xFFFB923C), // orange-400
                      bgColor: const Color(0x1AFB923C),
                      borderColor: const Color(0x33FB923C),
                      onTap: () => _handleFocus(item),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: LucideIcons.pause,
                      label: t.tr('staleTriage.actionOnHold'),
                      color: const Color(0xFFFBBF24), // amber-400
                      bgColor: const Color(0x1AFBBF24),
                      borderColor: const Color(0x33FBBF24),
                      onTap: () => _handlePause(item),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: LucideIcons.ban,
                      label: t.tr('staleTriage.actionDrop'),
                      color: const Color(0xFFFB7185), // rose-400
                      bgColor: const Color(0x1AFB7185),
                      borderColor: const Color(0x33FB7185),
                      onTap: () => _handleDrop(item),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: LucideIcons.bookmark,
                      label: t.tr('staleTriage.actionToPlanned'),
                      color: const Color(0xFF60A5FA), // blue-400
                      bgColor: const Color(0x1A60A5FA),
                      borderColor: const Color(0x3360A5FA),
                      onTap: () => _handleToPlanned(item),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
