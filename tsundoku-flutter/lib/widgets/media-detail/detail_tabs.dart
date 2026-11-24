/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/DetailTabs.svelte`.
///
/// Табы детальной страницы: скользящее подчёркивание (один физический
/// элемент, TabBar-indicator = label), бейджи эпизодов/галереи/related,
/// горизонтальный скролл на узких экранах.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import 'detail_types.dart';

/// Табы детальной страницы (1-в-1 с DetailTabs.svelte).
class DetailTabs extends ConsumerStatefulWidget {
  final SubTab active;
  final String mediaType;

  /// Undefined для не-shows; бейдж «3/12» на табе эпизодов.
  final ({int current, int? total})? seasonProgress;
  final int relatedCount;

  /// Пользовательские скриншоты на карточке; бейдж таба галереи.
  final int galleryCount;
  final void Function(SubTab tab) onSelect;

  const DetailTabs({
    super.key,
    required this.active,
    required this.mediaType,
    required this.seasonProgress,
    this.relatedCount = 0,
    this.galleryCount = 0,
    required this.onSelect,
  });

  @override
  ConsumerState<DetailTabs> createState() => _DetailTabsState();
}

class _DetailTabsState extends ConsumerState<DetailTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: _tabs.indexOf(widget.active).clamp(0, _tabs.length - 1),
  );

  List<SubTab> get _tabs {
    final tabs = <SubTab>[SubTab.overview];
    if (widget.mediaType == 'tvshow') tabs.add(SubTab.episodes);
    // Галерея — type-agnostic: скриншоты есть у любого тайтла.
    tabs.add(SubTab.gallery);
    tabs.add(SubTab.related);
    tabs.add(SubTab.recommendations);
    return tabs;
  }

  @override
  void didUpdateWidget(covariant DetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _tabs.indexOf(widget.active).clamp(0, _tabs.length - 1);
    if (_controller.index != index) {
      _controller.animateTo(index);
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

    return Semantics(
      label: 'Sections', // aria-label
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Горизонтальный скролл на узких экранах (nowrap-табы не влезают в
          // 320–390px); подчёркивание — единый элемент, скользит между
          // кнопками (TabBar-indicator, label-размер).
          TabBar(
            controller: _controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (index) => widget.onSelect(_tabs[index]),
            dividerColor: Colors.white.withAlpha(21), // border-white/[0.08]
            indicatorSize: TabBarIndicatorSize.label,
            indicatorColor: th.accent, // bg-[var(--color-accent)]
            indicatorWeight: 2, // h-0.5
            indicatorPadding:
                const EdgeInsets.symmetric(horizontal: 0), // во всю кнопку
            labelColor: Colors.white, // active → text-white
            unselectedLabelColor: th.textMuted, // text-muted
            labelStyle: const TextStyle(
              fontSize: 14, // text-sm
              fontWeight: FontWeight.w600, // font-semibold
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            labelPadding: const EdgeInsets.symmetric(
                horizontal: 12), // sm:px-4 (px-3 на мобиле)
            tabs: [
              for (final tab in _tabs)
                Tab(
                  height: 45, // py-2.5 (10px) + текст
                  child: _tabContent(t, th, tab),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabContent(I18nDictionary t, TsundokuTheme th, SubTab tab) {
    final badge = switch (tab) {
      SubTab.episodes when widget.seasonProgress != null =>
        _badge(
          '${widget.seasonProgress!.current}/${widget.seasonProgress!.total ?? '—'}',
          color: th.accentSoft, // text-[var(--color-accent-soft)]
        ),
      SubTab.gallery when widget.galleryCount > 0 =>
        _badge('${widget.galleryCount}', color: th.textMuted),
      SubTab.related when widget.relatedCount > 0 =>
        _badge('${widget.relatedCount}', color: th.textMuted),
      _ => null,
    };

    final label = switch (tab) {
      SubTab.overview => t.tr('detail.tabOverview'),
      SubTab.episodes => t.tr('detail.tabEpisodes'),
      SubTab.gallery => t.tr('detail.tabGallery'),
      SubTab.related => t.tr('detail.tabRelatedMedia'),
      SubTab.recommendations => t.tr('detail.tabRecommendations'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tab == SubTab.recommendations) ...[
          Icon(LucideIcons.sparkles,
              size: 14, color: th.accentSoft), // text-accent-soft
          const SizedBox(width: 8), // gap-2
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (badge != null) ...[
          const SizedBox(width: 8), // gap-2
          badge,
        ],
      ],
    );
  }

  Widget _badge(String text, {required Color color}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // px-2 py-0.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999), // rounded-full
        color: Colors.white.withAlpha(26), // bg-white/10
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12, // text-xs
          color: color,
        ),
      ),
    );
  }
}
