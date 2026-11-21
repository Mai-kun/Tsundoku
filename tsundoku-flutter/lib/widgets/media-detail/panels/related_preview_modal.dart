/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/panels/RelatedPreviewModal.svelte`.
///
/// Превью внешней записи из related: постер, бейджи типа/отношения/источника,
/// рейтинги-чипы (спиннер при загрузке), факт-строки (год/автор|студия/
/// счётчик), начальный статус + «Добавить в библиотеку», описание.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/model/cover_url.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/modal.dart';
import '../../../shared/ui/popover_menu.dart';
import '../detail_formatters.dart';
import '../detail_types.dart';

/// Превью-модал связанной записи (1-в-1 с RelatedPreviewModal.svelte).
class RelatedPreviewModal extends ConsumerWidget {
  /// Null, когда внешняя запись не превьюируется.
  final RelatedEntry? item;
  final List<RatingBadge> badges;
  final bool loading;
  final bool adding;
  final MediaStatus status;
  final void Function(MediaStatus status) onStatusChange;
  final void Function(MediaStatus status) onAdd;
  final VoidCallback onClose;

  const RelatedPreviewModal({
    super.key,
    required this.item,
    required this.badges,
    required this.loading,
    required this.adding,
    required this.status,
    required this.onStatusChange,
    required this.onAdd,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = item;
    if (entry == null) return const SizedBox.shrink();

    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    final statusOptions = <MediaStatus>[
      MediaStatus.planned,
      MediaStatus.inProgress,
      MediaStatus.completed,
      MediaStatus.onHold,
      MediaStatus.dropped,
    ];

    // Episodes / chapters / volumes: в порядке приоритета провайдера.
    ({int value, String unit})? count;
    if (entry.episodes != null && entry.episodes! > 0) {
      count = (value: entry.episodes!, unit: t.tr('searchModal.countUnits.anime'));
    } else if (entry.chapters != null && entry.chapters! > 0) {
      count = (value: entry.chapters!, unit: t.tr('searchModal.countUnits.manga'));
    } else if (entry.volumes != null && entry.volumes! > 0) {
      count = (value: entry.volumes!, unit: t.tr('searchModal.countUnits.manga'));
    }

    final isMangaLike = entry.type == 'manga' ||
        entry.format == 'NOVEL' ||
        entry.format == 'MANGA';

    return TsundokuModal(
      isOpen: true,
      onClose: onClose,
      size: ModalSize.md,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(24), // p-6
            child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Постер (мобайл по центру, sm — слева).
                              Container(
                                width: 160, // w-40 (2/3 → 240)
                                height: 240,
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(8), // rounded-lg
                                  color: th.bgCanvas, // bg-canvas
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: entry.coverUrl != null &&
                                        entry.coverUrl!.isNotEmpty
                                    ? Image.network(
                                        proxiedExternalCoverUrl(entry.coverUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : Center(
                                        child: Icon(LucideIcons.image,
                                            size: 32, color: th.textMuted),
                                      ),
                              ),
                              const SizedBox(width: 20), // gap-5
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Бейджи: тип / отношение / источник.
                                    Wrap(
                                      spacing: 8, // gap-2
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 2), // px-2.5 py-0.5
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            color: th
                                                .bgElevated, // bg-elevated
                                          ),
                                          child: Text(
                                            formatMediaDisplayType(
                                                entry.type, entry.format, t),
                                            style: TextStyle(
                                              fontSize: 11, // text-[11px]
                                              fontWeight:
                                                  FontWeight.w600, // font-semibold
                                              letterSpacing:
                                                  0.6, // tracking-wider
                                              color: th
                                                  .accentSoft, // text-accent-soft
                                            ),
                                          ),
                                        ),
                                        if (entry.relationType != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 2),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color: Colors.white
                                                      .withAlpha(
                                                          64)), // accent/40
                                              color: th.accent
                                                  .withAlpha(51), // accent/20
                                            ),
                                            child: Text(
                                              entry.relationType!,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: th.accentSoft,
                                              ),
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 2),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withAlpha(26)), // white/10
                                            color: th
                                                .bgSurface, // bg-field
                                          ),
                                          child: Text(
                                            'AniList',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: th.textMuted, // text-muted
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4), // mt-1
                                      child: Text(
                                        entry.title,
                                        style: const TextStyle(
                                          fontSize: 18, // text-lg
                                          fontWeight: FontWeight.w700, // font-bold
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (entry.originalTitle != null)
                                      Text(
                                        entry.originalTitle!,
                                        style: TextStyle(
                                          fontSize: 12, // text-xs
                                          color: th.textMuted, // text-muted
                                        ),
                                      ),
                                    // Рейтинги-чипы.
                                    if (badges.isNotEmpty)
                                      Wrap(
                                        spacing: 8, // gap-2
                                        runSpacing: 8,
                                        children: [
                                          for (final r in badges)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2), // px-2 py-0.5
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(6), // md
                                                border: Border.all(
                                                    color: Colors.white
                                                        .withAlpha(26)),
                                                color: th.bgSurface, // bg-field
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '${r.source}:',
                                                    style: TextStyle(
                                                      fontSize: 12, // text-xs
                                                      fontWeight:
                                                          FontWeight.w500, // font-medium
                                                      color:
                                                          th.textMuted, // text-muted
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4), // gap-1
                                                  if (r.score != null &&
                                                      r.score! > 0)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          LucideIcons.star,
                                                          size: 11,
                                                          color: th
                                                              .accentSoft, // text-star
                                                        ),
                                                        const SizedBox(
                                                            width: 2), // gap-0.5
                                                        Text(
                                                          r.score!
                                                              .toStringAsFixed(1),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w700, // font-bold
                                                            color:
                                                                th.accentSoft, // text-star
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  else if (loading)
                                                    const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: Color(
                                                                  0xFF94A3B8)),
                                                    )
                                                  else
                                                    Text(
                                                      '—',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: th.textMuted,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withAlpha(26)),
                                          color: th.bgSurface, // bg-field
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(LucideIcons.star,
                                                size: 11,
                                                color: th.textMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              t.tr('detail.previewModal.noRatings'),
                                              style: TextStyle(
                                                fontSize: 12, // text-xs
                                                color: th.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Факт-строки.
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _factRow(t, th, 'detail.previewModal.year',
                                            entry.year?.toString()),
                                        if (isMangaLike)
                                          _factRow(t, th,
                                              'detail.previewModal.author',
                                              entry.author)
                                        else
                                          _factRow(t, th,
                                              'detail.previewModal.studio',
                                              entry.studio),
                                        _factRow(
                                            t,
                                            th,
                                            'detail.previewModal.count',
                                            count != null
                                                ? '${count.value} ${count.unit}'
                                                : null),
                                      ],
                                    ),
                                    // Начальный статус + «Добавить в библиотеку».
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 8), // pt-2
                                      child: Wrap(
                                        spacing: 12, // gap-3
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${t.tr('detail.previewModal.initialStatus')}:',
                                                style: TextStyle(
                                                  fontSize: 12, // text-xs
                                                  fontWeight:
                                                      FontWeight.w500, // font-medium
                                                  color: th.textMuted, // text-muted
                                                ),
                                              ),
                                              const SizedBox(width: 8), // gap-2
                                              SizedBox(
                                                // Select: компактная ширина
                                                // (px-2.5 py-1.5 text-xs в Svelte).
                                                width: 200,
                                                child: TsundokuSelect<MediaStatus>(
                                                  id: 'preview-status',
                                                  options: [
                                                    for (final opt in statusOptions)
                                                      PopoverOption(
                                                          value: opt,
                                                          label:
                                                              statusLabel(opt, t)),
                                                  ],
                                                  value: status,
                                                  onChange: onStatusChange,
                                                  label: t.tr(
                                                      'detail.previewModal.initialStatus'),
                                                ),
                                              ),
                                            ],
                                          ),
                                          _AddToLibraryButton(
                                            adding: adding,
                                            addingLabel: t
                                                .tr('detail.previewModal.addingToLibrary'),
                                            addLabel: t
                                                .tr('detail.previewModal.addToLibrary'),
                                            th: th,
                                            onTap: () => onAdd(status),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Описание.
                          Container(
                            margin: const EdgeInsets.only(top: 20), // mt-5
                            padding: const EdgeInsets.only(top: 16), // pt-4
                            decoration: const BoxDecoration(
                              border: Border(
                                  top: BorderSide(
                                      color: Colors.white)), // border-border
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.tr('detail.previewModal.description'),
                                  style: TextStyle(
                                    fontSize: 12, // text-xs
                                    fontWeight:
                                        FontWeight.w600, // font-semibold
                                    letterSpacing: 0.6, // tracking-wider
                                    color: th.textMuted, // text-muted
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6), // mt-1.5
                                  child: Text(
                                    entry.description?.isNotEmpty ?? false
                                        ? entry.description!
                                        : t.tr('detail.previewModal.noDescription'),
                                    style: TextStyle(
                                      fontSize: 12, // text-xs
                                      height: 1.625, // leading-relaxed
                                      fontStyle: (entry.description?.isEmpty ??
                                              true)
                                          ? FontStyle.italic // нет описания
                                          : FontStyle.normal,
                                      color: (entry.description?.isEmpty ??
                                              true)
                                          ? th.textMuted.withAlpha(178) // /70
                                          : th.textMuted, // text-muted
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          // X-кнопка (tap hover bg-elevated/text-ink).
          Positioned(
            top: 16, // top-4
            right: 16,
            child: _PreviewCloseButton(
              label: t.tr('common.close'),
              th: th,
              onClose: onClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _factRow(
      I18nDictionary t, TsundokuTheme th, String labelKey, String? value) {
    final locale = t.locale;
    final isRu = locale.wire == 'ru';
    final noData = isRu ? 'Нет данных' : 'No data'; // previewModal.noData
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // space-y-1
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${t.tr(labelKey)}:',
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w500, // font-medium
              color: th.textPrimary, // text-ink
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value ?? noData,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: th.textMuted, // text-muted
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// X-кнопка: hover bg-elevated/text-ink.
class _PreviewCloseButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onClose;

  const _PreviewCloseButton({
    required this.label,
    required this.th,
    required this.onClose,
  });

  @override
  State<_PreviewCloseButton> createState() => _PreviewCloseButtonState();
}

class _PreviewCloseButtonState extends State<_PreviewCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 32, // h-8 w-8
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                color: _hovered
                    ? widget.th.bgElevated // hover:bg-elevated
                    : Colors.transparent,
              ),
              child: Icon(
                LucideIcons.x,
                size: 18,
                color: _hovered
                    ? widget.th.textPrimary // hover:text-ink
                    : widget.th.textMuted, // text-muted
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Добавить в библиотеку»: спиннер при adding.
class _AddToLibraryButton extends StatelessWidget {
  final bool adding;
  final String addingLabel;
  final String addLabel;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _AddToLibraryButton({
    required this.adding,
    required this.addingLabel,
    required this.addLabel,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: adding ? null : onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // px-4 py-2
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), // rounded-lg
          border: Border.all(
            color: Colors.white.withAlpha(26), // border-white/10
          ),
          color: th.bgSurface, // bg-field
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (adding)
              SizedBox(
                width: 16, // h-4 w-4
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: th.accent, // border-accent
                ),
              )
            else
              Icon(LucideIcons.plus,
                  size: 16,
                  color: th.textPrimary // text-ink
                  ),
            const SizedBox(width: 8), // gap-2
            Text(
              adding ? addingLabel : addLabel,
              style: TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w600, // font-semibold
                color: th.textPrimary, // text-ink
              ),
            ),
          ],
        ),
      ),
    );
  }
}
