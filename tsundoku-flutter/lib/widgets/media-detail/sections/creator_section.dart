/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/CreatorSection.svelte`.
///
/// «Визитка создателя»: шапка (фото/иконка + лейбл роли + имя + ★средняя),
/// строка освоения коллекции (градиент-бар), команда создателей (staff,
/// размер карточек по категории), галерея других работ.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/model/cover_url.dart';
import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/lightbox.dart';
import '../../../shared/utils/ui_settings.dart';
import '../../../shared/utils/unknown_creator.dart';
import 'people_size_toggle.dart';

/// Разработчик / developer — для иконки Gamepad.
final RegExp _developerRe = RegExp('разработчик|developer', caseSensitive: false);

/// Секция создателя (1-в-1 с CreatorSection.svelte).
class CreatorSection extends ConsumerStatefulWidget {
  final String creatorName;
  final CreatorRole role;
  final String? mediaType;

  /// Переопределяет дефолт-подпись роли (network, mangaka, developer).
  final String? label;
  final String currentMediaId;
  final String? imageUrl;

  /// Ключ crew из staff-снапшота; рендерится и без студии.
  final List<StaffMember> staff;

  /// Ключ категории (аниме — своя) для размера staff-карточек.
  final String category;
  final void Function(MediaItem item) onOpenMedia;
  final void Function(String query) onSearch;

  const CreatorSection({
    super.key,
    required this.creatorName,
    required this.role,
    this.mediaType,
    this.label,
    required this.currentMediaId,
    this.imageUrl,
    this.staff = const [],
    required this.category,
    required this.onOpenMedia,
    required this.onSearch,
  });

  @override
  ConsumerState<CreatorSection> createState() => _CreatorSectionState();
}

class _CreatorSectionState extends ConsumerState<CreatorSection> {
  CreatorSummaryDto? _summary;
  bool _loading = true;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant CreatorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect-аналог: смена (name, role, id) → перезагрузка сводки.
    if (oldWidget.creatorName != widget.creatorName ||
        oldWidget.role != widget.role ||
        oldWidget.currentMediaId != widget.currentMediaId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final name = widget.creatorName;
    if (isUnknownCreatorName(name)) {
      // Нет студии/автора — или плейсхолдер («Неизвестный автор»), который
      // не должен группировать несвязанные тайтлы: карточка рендерится,
      // но только с staff-сеткой.
      if (mounted) {
        setState(() {
          _loading = false;
          _summary = null;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final value = await ref
          .read(apiClientProvider)
          .getCreatorSummary(name, widget.role, excludeId: widget.currentMediaId);
      if (!mounted) return;
      setState(() => _summary = value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _summary = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final settings = ref.watch(uiSettingsProvider);
    final isRu = locale.wire == 'ru';
    final largeStaff =
        settings.staffSizeByCategory[widget.category] == PeopleCardSize.large;
    final summary = _summary;

    final completionPercent = (summary != null && summary.totalCount > 0)
        ? ((summary.completedCount / summary.totalCount) * 100).round()
        : 0;

    String displayLabel;
    if (widget.label != null && widget.label!.isNotEmpty) {
      displayLabel = widget.label!.toUpperCase();
    } else if (widget.mediaType == 'game') {
      displayLabel = isRu ? 'РАЗРАБОТЧИК' : 'DEVELOPER';
    } else if (widget.role == CreatorRole.studio) {
      displayLabel = isRu ? 'СТУДИЯ' : 'STUDIO';
    } else if (widget.role == CreatorRole.director) {
      displayLabel = isRu ? 'РЕЖИССЁР' : 'DIRECTOR';
    } else {
      displayLabel = isRu ? 'АВТОР' : 'AUTHOR';
    }

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
        color: th.bgSurface, // panel-line
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Шапка («Визитка создателя»).
          if (widget.creatorName.isNotEmpty)
            Row(
              children: [
                if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: () => ref
                        .read(lightboxProvider.notifier)
                        .openLightbox(widget.imageUrl, widget.creatorName),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                      child: Container(
                        width: 40, // size-10
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: th.accent.withAlpha(77)), // border-accent/30
                          color: th.accent.withAlpha(38), // bg-accent/15
                        ),
                        child: Image.network(
                          widget.imageUrl!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 40, // size-10
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                      border: Border.all(
                          color: th.accent.withAlpha(77)), // border-accent/30
                      color: th.accent.withAlpha(38), // bg-accent/15
                    ),
                    child: Icon(
                      _creatorIcon(widget.mediaType, widget.label, widget.role),
                      size: 20,
                      color: th.accentSoft, // text-accent-soft
                    ),
                  ),
                const SizedBox(width: 12), // gap-3
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10, // text-[10px]
                          fontWeight: FontWeight.w700, // font-bold
                          letterSpacing: 0.6, // tracking-wider
                          color: th.textMuted, // text-muted
                        ),
                      ),
                      Text(
                        widget.creatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16, // text-base
                          fontWeight: FontWeight.w800, // font-extrabold
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Правая часть: ★средняя + поиск.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (summary?.averageScore != null)
                      Tooltip(
                        message:
                            '${isRu ? 'Средняя оценка' : 'Average score'}: ${summary!.averageScore!.toStringAsFixed(1)}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4), // px-2.5 py-1
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0x4DFBBF24)), // amber-400/30
                            color: const Color(0x1AFBBF24), // amber-400/10
                          ),
                          child: Text(
                            '★ ${summary.averageScore!.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w900, // font-black
                              color: Color(0xFFFCD34D), // text-amber-300
                            ),
                          ),
                        ),
                      ),
                    if (!isUnknownCreatorName(widget.creatorName)) ...[
                      const SizedBox(width: 8), // gap-2
                      MouseRegion(
                        onEnter: (_) => setState(() => _hovered = true),
                        onExit: (_) => setState(() => _hovered = false),
                        child: GestureDetector(
                          onTap: () => widget.onSearch(widget.creatorName),
                          child: Tooltip(
                            message: isRu
                                ? 'Искать другие работы в базе'
                                : 'Search other works',
                            child: Container(
                              width: 32, // size-8
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(8), // rounded-lg
                                border: Border.all(
                                    color: _hovered
                                        ? th.accent
                                            .withAlpha(102) // hover:border-accent/40
                                        : Colors.white
                                            .withAlpha(26)), // border-white/10
                                color: _hovered
                                    ? th.accent.withAlpha(
                                        26) // hover:bg-accent/10
                                    : Colors.white.withAlpha(10), // /[0.04]
                              ),
                              child: Icon(
                                LucideIcons.search,
                                size: 15,
                                color: _hovered
                                    ? th.accentSoft // hover:text-accent-soft
                                    : th.textMuted, // text-muted
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          const SizedBox(height: 14), // space-y-3.5
          // 2. Компактная строка освоения коллекции.
          if (summary != null)
            Container(
              padding: const EdgeInsets.all(10), // p-2.5
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                    color: Colors.white.withAlpha(13)), // border-white/5
                color: Colors.white.withAlpha(8), // bg-white/[0.03]
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '${isRu ? 'В вашей коллекции' : 'In your library'}: ',
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted, // text-muted
                        ),
                      ),
                      Text(
                        '${summary.totalCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600, // font-semibold
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        ' • ${isRu ? 'Завершено' : 'Completed'}: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: th.textMuted,
                        ),
                      ),
                      Text(
                        '${summary.completedCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        ' ($completionPercent%)',
                        style: TextStyle(
                          fontSize: 12,
                          color: th.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8), // space-y-2
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 6, // h-1.5
                      decoration: BoxDecoration(
                        border: Border.all(
                            color:
                                Colors.white.withAlpha(10)), // border-white/[0.04]
                        color: th.bgSurface, // color-field
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        alignment: Alignment.centerLeft,
                        width: MediaQuery.sizeOf(context).width *
                            0.4 *
                            (completionPercent.clamp(0, 100) / 100),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              th.accentBright, // from-accent-bright
                              const Color(0xFF818CF8), // to-[#818cf8]
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_loading)
            Container(
              height: 40, // h-10
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withAlpha(8), // bg-white/[0.03]
              ),
            ),
          // 2.5 Команда создателей.
          if (widget.staff.isNotEmpty) ...[
            const SizedBox(height: 14), // space-y-3.5
            Container(
              padding: const EdgeInsets.only(top: 12), // pt-3
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Color(0x0FFFFFFF))), // /[0.06]
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.tr('creator.staffHeading'),
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            fontWeight: FontWeight.w700, // font-bold
                            letterSpacing: 0.6, // tracking-wider
                            color: Color(0xFFCBD5E1), // text-slate-300
                          ),
                        ),
                      ),
                      PeopleSizeToggle(
                          category: widget.category, block: PeopleBlock.staff),
                    ],
                  ),
                  const SizedBox(height: 10), // gap-2.5
                  Wrap(
                    spacing: 10, // gap-2.5
                    runSpacing: 10,
                    children: [
                      for (var idx = 0; idx < widget.staff.length; idx++)
                        _StaffCard(
                          person: widget.staff[idx],
                          large: largeStaff,
                          th: th,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // 3. Галерея других работ.
          if (summary != null && summary.otherItems.isNotEmpty) ...[
            const SizedBox(height: 14), // space-y-3.5
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tr('creator.otherWorks'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 8), // space-y-2
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal, // overflow-x-auto
                  child: Row(
                    children: [
                      for (final item in summary.otherItems)
                        _OtherWorkCard(
                          item: item,
                          isRu: isRu,
                          th: th,
                          onOpen: () => widget.onOpenMedia(item),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _creatorIcon(String? mediaType, String? label, CreatorRole role) {
    if (mediaType == 'game' ||
        (label != null && _developerRe.hasMatch(label))) {
      return LucideIcons.gamepad2;
    }
    if (mediaType == 'book' || mediaType == 'manga' || role == CreatorRole.author) {
      return LucideIcons.bookOpen;
    }
    return LucideIcons.clapperboard;
  }
}

/// Карточка staff: фото (lightbox) / буква-плейсхолдер + имя/роль.
class _StaffCard extends StatelessWidget {
  final StaffMember person;
  final bool large;
  final TsundokuTheme th;

  const _StaffCard({
    required this.person,
    required this.large,
    required this.th,
  });

  @override
  Widget build(BuildContext context) {
    final ref = ProviderScope.containerOf(context);
    return Container(
      padding: const EdgeInsets.all(10), // p-2.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
        color: Colors.white.withAlpha(8), // bg-white/[0.03]
      ),
      width: large ? 300 : 260,
      child: Row(
        crossAxisAlignment:
            large ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (person.imageUrl != null && person.imageUrl!.isNotEmpty)
            GestureDetector(
              onTap: () {
                ref.read(lightboxProvider.notifier).openLightbox(person.imageUrl);
              },
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(large ? 12 : 8), // rounded-xl / lg
                child: Container(
                  width: large ? 64 : 40, // w-16 / size-10
                  height: large ? 80 : 40, // h-20 / size-10
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.white.withAlpha(26)), // ring-white/10
                  ),
                  child: Image.network(
                    person.imageUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            )
          else
            Container(
              width: large ? 64 : 40,
              height: large ? 80 : 40,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(large ? 12 : 8), // rounded-xl / lg
                color: Colors.white.withAlpha(13), // bg-white/5
                border: Border.all(
                    color: Colors.white.withAlpha(26)), // ring-white/10
              ),
              child: Center(
                child: Text(
                  person.name.isEmpty
                      ? ''
                      : person.name
                          .substring(0, 1)
                          .toUpperCase(), // первая буква имени
                  style: TextStyle(
                    fontSize: 11, // text-[11px]
                    fontWeight: FontWeight.w700, // font-bold
                    color: th.textMuted, // text-muted
                  ),
                ),
              ),
            ),
          SizedBox(width: large ? 12 : 10), // gap-3 / gap-2.5
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: large ? 2 : 1, // line-clamp-2 / truncate
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 14 : 12, // text-sm / text-xs
                    height: large ? 1.375 : null, // leading-snug
                    fontWeight: FontWeight.w700, // font-bold
                    color: Colors.white,
                  ),
                ),
                if (person.role != null && person.role!.isNotEmpty)
                  Padding(
                    padding: large
                        ? const EdgeInsets.only(top: 4) // mt-1
                        : EdgeInsets.zero,
                    child: Text(
                      person.role!,
                      maxLines: large ? 2 : 1, // line-clamp-2 / truncate
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: large ? 12 : 11, // text-xs / text-[11px]
                        color: th.textMuted, // text-muted
                      ),
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

/// Карточка другой работы: постер 2/3 + title + статус + ★score.
class _OtherWorkCard extends StatelessWidget {
  final MediaItem item;
  final bool isRu;
  final TsundokuTheme th;
  final VoidCallback onOpen;

  const _OtherWorkCard({
    required this.item,
    required this.isRu,
    required this.th,
    required this.onOpen,
  });

  String _statusLabel(MediaStatus status) {
    switch (status) {
      case MediaStatus.planned:
        return 'В планах';
      case MediaStatus.inProgress:
        return 'Смотрю';
      case MediaStatus.completed:
        return 'Завершено';
      case MediaStatus.onHold:
        return 'Отложено';
      case MediaStatus.dropped:
        return 'Брошено';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12), // gap-3
      child: GestureDetector(
        onTap: onOpen,
        child: SizedBox(
          width: 112, // w-28
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  border: Border.all(
                      color: Colors.white.withAlpha(15)), // /[0.06]
                  color: Colors.black.withAlpha(51), // bg-black/20
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 2 / 3, // aspect-[2/3]
                  child: item.coverUrl != null
                      ? Image.network(
                          proxiedExternalCoverUrl(item.coverUrl!),
                          fit: BoxFit.cover,
                        )
                      : Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8), // px-2
                            child: Text(
                              item.title,
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12, // text-xs
                                color: th.textMuted, // text-muted
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6), // mt-1.5
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: Colors.white,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _statusLabel(item.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11, // text-[11px]
                        color: th.textMuted, // text-muted
                      ),
                    ),
                  ),
                  if (item.score != null)
                    Text(
                      '★ ${item.score}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700, // font-bold
                        color: Color(0xFFFCD34D), // text-amber-300
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
