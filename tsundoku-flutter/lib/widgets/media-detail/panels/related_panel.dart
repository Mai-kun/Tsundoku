/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/panels/RelatedPanel.svelte`.
///
/// Панель связанных: заголовок + RelationLoadButton, три режима вида
/// (grouped/timeline/grid), авто-загрузка дефолтного источника, скелетон,
/// error-блок (Steam Deck greys), timeline-строки с маркерами.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/ui/media_status_badge.dart';
import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/tsundoku_image.dart';
import '../detail_formatters.dart';
import '../detail_types.dart';
import '../relation_load_button.dart';
import '../relation_sources.dart';

/// Литералы токенов вне ThemeExtension (как warning-line/success-deep).
const Color _kOverlayStrong = Color(0xFF1E222D); // --color-overlay-strong
const Color _kTrackAlt = Color(0xFF181B24); // --color-track-alt
const Color _kShellGrey = Color(0xFF1C202B); // #1c202b

/// Панель связанных (1-в-1 с RelatedPanel.svelte).
class RelatedPanel extends ConsumerStatefulWidget {
  final MediaItem media;
  final List<RelatedEntry> related;
  final bool loading;
  final Object? error;
  final RelatedViewMode viewMode;
  final List<RelationGroup> groups;
  final List<TimelineEntry> timeline;
  final VoidCallback onRetry;
  final void Function(RelatedViewMode mode) onSelectViewMode;

  /// Открывает локальный тайтл или превью-модал внешнего.
  final void Function(RelatedEntry entry) onOpen;

  /// force пропускает 30-дневный кэш; source — выбор в дропдауне.
  final void Function(String source, {bool force}) onLoadFrom;

  const RelatedPanel({
    super.key,
    required this.media,
    this.related = const [],
    this.loading = false,
    this.error,
    this.viewMode = RelatedViewMode.grouped,
    this.groups = const [],
    this.timeline = const [],
    required this.onRetry,
    required this.onSelectViewMode,
    required this.onOpen,
    required this.onLoadFrom,
  });

  @override
  ConsumerState<RelatedPanel> createState() => _RelatedPanelState();
}

class _RelatedPanelState extends ConsumerState<RelatedPanel> {
  String _autoLoadedMediaId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLoad());
  }

  @override
  void didUpdateWidget(covariant RelatedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoLoad());
    }
  }

  /// $effect-аналог: не загружено и не грузится → дефолтный источник.
  Future<void> _autoLoad() async {
    final media = widget.media;
    if (media.id.isEmpty ||
        _autoLoadedMediaId == media.id ||
        widget.loading ||
        widget.error != null ||
        widget.related.isNotEmpty) {
      return;
    }
    _autoLoadedMediaId = media.id;
    try {
      final list =
          await availableRelationSources(ref.read(apiClientProvider), media);
      if (!mounted) return;
      if (widget.loading ||
          widget.error != null ||
          widget.related.isNotEmpty ||
          media.id != widget.media.id) {
        return;
      }
      String? defaultSource;
      for (final s in list) {
        final detail = media is MediaDetail ? media : null;
      final relatedSource = detail?.relatedSource?.toLowerCase();
        if (relatedSource != null &&
            relatedSource.isNotEmpty &&
            (s.id.toLowerCase() == relatedSource ||
                s.label.toLowerCase() == relatedSource)) {
          defaultSource = s.id;
          break;
        }
      }
      if (defaultSource == null) {
        for (final s in list) {
          final externalSource = media.externalSource?.toLowerCase();
          if (externalSource != null &&
              externalSource.isNotEmpty &&
              (s.id.toLowerCase() == externalSource ||
                  s.label.toLowerCase() == externalSource)) {
            defaultSource = s.id;
            break;
          }
        }
      }
      defaultSource ??= list.firstOrNull?.id;
      defaultSource ??= isAnime(media) || media.type == MediaType.manga
          ? 'anilist'
          : media.type == MediaType.game
              ? 'rawg'
              : 'tmdb';
      widget.onLoadFrom(defaultSource);
    } catch (_) {
      // Список источников недоступен — авто-загрузка откладывается.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final isRu = locale.wire == 'ru';

    final views = <({RelatedViewMode mode, String title, IconData icon})>[
      (mode: RelatedViewMode.grouped, title: t.tr('detail.viewGrouped'), icon: LucideIcons.layers),
      (mode: RelatedViewMode.timeline, title: t.tr('detail.viewTimeline'), icon: LucideIcons.gitBranch),
      (mode: RelatedViewMode.grid, title: t.tr('detail.viewGrid'), icon: LucideIcons.layoutGrid),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.tr('detail.relatedTitle').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14, // text-sm
                      fontWeight: FontWeight.w700, // font-bold
                      letterSpacing: 0.6, // tracking-wider
                      color: Color(0xFFCBD5E1), // text-slate-300
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.tr('detail.relatedSubtitle'),
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      color: th.textMuted, // text-muted
                    ),
                  ),
                  // Остаётся в шапке после успешной загрузки.
                  if (widget.related.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12), // mt-3
                      child: RelationLoadButton(
                        media: widget.media,
                        loading: widget.loading,
                        kind: 'related',
                        currentSource: widget.media is MediaDetail
                            ? (widget.media as MediaDetail).relatedSource
                            : null,
                        onLoad: (source, {force = false}) =>
                            widget.onLoadFrom(source, force: force),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.related.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(4), // p-1
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  border: Border.all(
                      color: Colors.white.withAlpha(21)), // /[0.08]
                  color: _kTrackAlt, // color-track-alt
                ),
                child: Wrap(
                  spacing: 4, // gap-1
                  children: [
                    for (final view in views)
                      Tooltip(
                        message: view.title,
                        child: Semantics(
                          button: true,
                          label: view.title,
                          selected: widget.viewMode == view.mode,
                          child: GestureDetector(
                            onTap: () => widget.onSelectViewMode(view.mode),
                            child: Container(
                              width: 32, // h-8 w-8
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(6), // rounded-md
                                color: widget.viewMode == view.mode
                                    ? th.accent // bg-accent
                                    : Colors.transparent,
                                boxShadow: widget.viewMode == view.mode
                                    ? const [
                                        BoxShadow(
                                            color: Color(0x33000000),
                                            offset: Offset(0, 1),
                                            blurRadius: 2),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                view.icon,
                                size: 17,
                                color: widget.viewMode == view.mode
                                    ? Colors.white
                                    : _hoverIcon(context, view.mode),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24), // space-y-6
        if (widget.loading)
          _loadingGrid(th)
        else if (widget.error != null)
          _errorBlock(t, th, isRu)
        else if (widget.related.isEmpty)
          _emptyBlock(t, th, isRu)
        else if (widget.viewMode == RelatedViewMode.grouped)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in widget.groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 32), // space-y-8
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.only(bottom: 10), // pb-2.5
                        margin:
                            const EdgeInsets.only(bottom: 12), // space-y-3
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: Color(0x14FFFFFF))), // /[0.08]
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.title,
                                style: const TextStyle(
                                  fontSize: 18, // sm:text-lg
                                  fontWeight: FontWeight.w700, // font-bold
                                  letterSpacing: -0.25, // tracking-tight
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10), // gap-2.5
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2), // px-2.5 py-0.5
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Colors.white.withAlpha(26), // white/10
                              ),
                              child: Text(
                                '${group.items.length}',
                                style: TextStyle(
                                  fontSize: 12, // text-xs
                                  fontWeight: FontWeight.w700, // font-bold
                                  color: th.textMuted, // text-muted
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _cardGrid(context, group.items, th),
                    ],
                  ),
                ),
            ],
          )
        else if (widget.viewMode == RelatedViewMode.timeline)
          Column(
            children: [
              for (final item in widget.timeline)
                _TimelineRow(
                  item: item,
                  th: th,
                  t: t,
                  onOpen: () {
                    if (item.isCurrent || item.rawItem == null) return;
                    widget.onOpen(item.rawItem!);
                  },
                ),
            ],
          )
        else
          _cardGrid(context, widget.related, th),
      ],
    );
  }

  Color? _hoverIcon(BuildContext context, RelatedViewMode mode) {
    // hover:text-white — в тестах цвет idle; hover-стейт отдаёт MouseRegion.
    return const Color(0xFF94A3B8); // text-slate-400
  }

  Widget _cardGrid(BuildContext context, List<RelatedEntry> entries, TsundokuTheme th) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024
        ? 5
        : width >= 768
            ? 4
            : width >= 640
                ? 3
                : 2;
    final gap = 12.0; // gap-3
    final cardWidth = ((width - 48 - gap * (columns - 1)) / columns)
        .clamp(120.0, 400.0);

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final rel in entries)
          SizedBox(
            width: cardWidth,
            child: _RelatedCard(rel: rel, th: th, onOpen: () => widget.onOpen(rel)),
          ),
      ],
    );
  }

  Widget _loadingGrid(TsundokuTheme th) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024
        ? 5
        : width >= 768
            ? 4
            : width >= 640
                ? 3
                : 2;
    final gap = 12.0;
    final cardWidth = ((width - 48 - gap * (columns - 1)) / columns)
        .clamp(120.0, 400.0);

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (var idx = 0; idx < 5; idx++)
          SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12), // rounded-xl
                    color: th.bgSurface, // panel-line
                  ),
                  child: AspectRatio(aspectRatio: 2 / 3),
                ),
                const SizedBox(height: 8), // space-y-2
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.75, // w-3/4
                  child: Container(
                    height: 12, // h-3
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: th.bgSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _errorBlock(I18nDictionary t, TsundokuTheme th, bool isRu) {
    final locale = ref.read(i18nProvider);
    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(
            color: const Color(0x33F87171)), // border-rose-400/20
        color: _kShellGrey, // bg-[#1c202b]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true, // role="alert"
            child: Text(
              errorMessage(widget.error!, locale),
              style: const TextStyle(
                fontSize: 14, // text-sm
                color: Color(0xFFFECDD3), // text-rose-200
              ),
            ),
          ),
          const SizedBox(height: 12), // gap-3
          _RetryButton(
            label: isRu ? 'Попробовать снова' : 'Try again',
            th: th,
            onTap: widget.onRetry,
          ),
        ],
      ),
    );
  }

  Widget _emptyBlock(I18nDictionary t, TsundokuTheme th, bool isRu) {
    return Container(
      padding: const EdgeInsets.all(32), // p-8
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        color: th.bgSurface, // panel-line
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            t.tr('detail.relatedEmpty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14, // text-sm
              fontWeight: FontWeight.w500, // font-medium
              color: Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
          const SizedBox(height: 4), // space-y-1
          Text(
            isRu
                ? 'Нажмите кнопку ниже, чтобы загрузить связанные произведения.'
                : 'Click the button below to load related titles.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12, // text-xs
              color: th.textMuted, // text-muted
            ),
          ),
          const SizedBox(height: 16), // gap-4
          RelationLoadButton(
            media: widget.media,
            loading: widget.loading,
            kind: 'related',
            currentSource: widget.media is MediaDetail
                ? (widget.media as MediaDetail).relatedSource
                : null,
            onLoad: (source, {force = false}) =>
                widget.onLoadFrom(source, force: force),
          ),
        ],
      ),
    );
  }
}

/// Кнопка повтора: accent/40 border, RefreshCw.
class _RetryButton extends StatefulWidget {
  final String label;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _RetryButton({
    required this.label,
    required this.th,
    required this.onTap,
  });

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6), // px-3 py-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: Border.all(
                color: widget.th.accent.withAlpha(102)), // accent/40
            color: _hovered
                ? widget.th.accent.withAlpha(51) // hover:accent/20
                : widget.th.accent.withAlpha(26), // accent/10
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.refreshCw,
                  size: 14,
                  color: _hovered
                      ? Colors.white
                      : widget.th.accentSoft), // text-accent-soft
              const SizedBox(width: 8), // gap-2
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: _hovered ? Colors.white : widget.th.accentSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка related: постер 2/3 + статус-бейдж локального + score + тип/год.
class _RelatedCard extends ConsumerWidget {
  final RelatedEntry rel;
  final TsundokuTheme th;
  final VoidCallback onOpen;

  const _RelatedCard({
    required this.rel,
    required this.th,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final th = this.th;
    final t = ref.watch(tProvider);
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
          color: _kOverlayStrong, // color-overlay-strong
        ),
        child: AspectRatio(
          aspectRatio: 2 / 3, // aspect-[2/3]
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (rel.coverUrl != null && rel.coverUrl!.isNotEmpty)
                TsundokuImage(
                  imageUrl: rel.coverUrl,
                  fit: BoxFit.cover,
                )
              else
                Container(
                  color: th.bgSurface, // color-field
                  child: Center(
                    child: Icon(LucideIcons.image,
                        size: 32, color: th.textMuted),
                  ),
                ),
              if (rel.localItem != null)
                Positioned(
                  top: 10, // top-2.5
                  left: 10,
                  child: Row(
                    children: [
                      MediaStatusBadge(
                        id: 'related-status-${rel.id}',
                        status: rel.localItem!.status,
                        onSelect: (_) => onOpen(),
                      ),
                      if (rel.localItem!.score != null &&
                          rel.localItem!.score! > 0)
                        Transform.translate(
                          offset: const Offset(-8, 0), // -ml-2 (#27)
                          child: Tooltip(
                            message:
                                '${rel.localItem!.score}',
                            child: Container(
                              width: 28, // h-7 w-7
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF4A63C9), // score-bg
                                border: Border.all(
                                    color: Colors.white.withAlpha(51)),
                              ),
                              child: Center(
                                child: Text(
                                  '${rel.localItem!.score}',
                                  style: const TextStyle(
                                    fontSize: 12, // text-xs
                                    fontWeight: FontWeight.w900, // font-black
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              // Градиент-подложка заголовка.
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 48, 12, 12), // p-3 pt-12
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xF2000000), // from-black/95
                        Color(0xD9000000), // via-black/85
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rel.title,
                        maxLines: 2, // line-clamp-2
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14, // text-sm
                          height: 1.375, // leading-snug
                          fontWeight: FontWeight.w700, // font-bold
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6), // mt-1.5
                      Row(
                        children: [
                          if (rel.relationType != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2), // px-2 py-0.5
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: Colors.white.withAlpha(
                                        64)), // border-accent/40
                                color: Colors.white.withAlpha(
                                    38), // bg-accent/25
                              ),
                              child: Text(
                                rel.relationType!,
                                style: const TextStyle(
                                  fontSize: 11, // text-[11px]
                                  fontWeight: FontWeight.w600, // font-semibold
                                  color: Color(0xFFA5B4FC), // accent-soft
                                ),
                              ),
                            )
                          else
                            Text(
                              formatMediaDisplayType(
                                  rel.type, rel.format, t),
                              style: const TextStyle(
                                fontSize: 11, // text-[11px]
                                color: Color(0xFFCBD5E1), // text-slate-300
                              ),
                            ),
                          const Spacer(),
                          if (rel.year != null)
                            Text(
                              '${rel.year}',
                              style: const TextStyle(
                                fontSize: 11, // text-[11px]
                                fontWeight: FontWeight.w500, // font-medium
                                color: Color(0xFFCBD5E1), // text-slate-300
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Timeline-строка: маркер (текущий/локальный/внешний) + карточка.
class _TimelineRow extends StatelessWidget {
  final TimelineEntry item;
  final TsundokuTheme th;
  final I18nDictionary t;
  final VoidCallback onOpen;

  const _TimelineRow({
    required this.item,
    required this.th,
    required this.t,
    required this.onOpen,
  });

  Color relatedStatusColor(MediaStatus status) {
    final colors = relatedStatusColors(status);
    return colors.background;
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = item.isCurrent;
    final hasLocal = item.localItem != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16), // space-y-4
      child: Row(
        children: [
          // Маркер на вертикальной линии (before-градиент ⏭️ — линия убрана,
          // маркеры 1-в-1 по цветам).
          Container(
            width: 24, // h-6 w-6
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                width: 2,
                color: isCurrent
                    ? th.accent // border-accent
                    : hasLocal
                        ? const Color(0xFF10B981) // border-emerald-500
                        : Colors.white.withAlpha(36), // /[0.14]
              ),
              color: th.bgSurface, // color-field
            ),
            child: Center(
              child: isCurrent
                  ? Container(
                      width: 8, // h-2 w-2
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    )
                  : hasLocal
                      ? const Icon(LucideIcons.check,
                          size: 12, color: Color(0xFF34D399)) // emerald-400
                      : Container(
                          width: 6, // h-1.5 w-1.5
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(102), // /40
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 16), // gap-4
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              child: Container(
                padding: const EdgeInsets.all(10), // p-2.5
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12), // rounded-xl
                  border: Border.all(
                    color: isCurrent
                        ? th.accent.withAlpha(153) // border-accent/60
                        : Colors.white.withAlpha(15), // /[0.06]
                  ),
                  color: isCurrent
                      ? th.accent.withAlpha(26) // bg-accent/10
                      : th.bgSurface, // panel-line
                ),
                child: Row(
                  children: [
                    // Постер 2/3 h-16.
                    Container(
                      width: 48, // h-16 при 2/3 → ширина ≈ 48
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8), // rounded-lg
                        color: th.bgSurface, // color-field
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: item.coverUrl != null &&
                              item.coverUrl!.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                TsundokuImage(
                                  imageUrl: item.coverUrl,
                                  fit: BoxFit.cover,
                                ),
                                if (hasLocal)
                                  Positioned(
                                    top: 4, // top-1
                                    left: 4,
                                    child: Container(
                                      width: 16, // h-4 w-4
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: relatedStatusColor(
                                            item.localItem!.status),
                                      ),
                                      child: item.localItem!.status ==
                                              MediaStatus.completed
                                          ? const Icon(LucideIcons.check,
                                              size: 8, color: Colors.white)
                                          : null,
                                    ),
                                  ),
                              ],
                            )
                          : Center(
                              child: Icon(LucideIcons.image,
                                  size: 18, color: th.textMuted),
                            ),
                    ),
                    const SizedBox(width: 14), // gap-3.5
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8, // gap-2
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (item.year != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2), // px-1.5 py-0.5
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: Colors.white.withAlpha(26), // white/10
                                  ),
                                  child: Text(
                                    '${item.year}',
                                    style: const TextStyle(
                                      fontSize: 11, // text-[11px]
                                      fontWeight: FontWeight.w700, // font-bold
                                      color: Color(0xFFA5B4FC), // accent-soft
                                    ),
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: isCurrent
                                      ? th.accent // bg-accent
                                      : Colors.white.withAlpha(13), // bg-white/5
                                  border: isCurrent
                                      ? null
                                      : Border.all(
                                          color: Colors.white
                                              .withAlpha(21)), // /[0.08]
                                ),
                                child: Text(
                                  item.relationType,
                                  style: TextStyle(
                                    fontSize: 10, // text-[10px]
                                    fontWeight: FontWeight.w600, // font-semibold
                                    color: isCurrent
                                        ? Colors.white
                                        : const Color(0xFFCBD5E1), // slate-300
                                  ),
                                ),
                              ),
                              Text(
                                item.formatDisplay,
                                style: TextStyle(
                                  fontSize: 11, // text-[11px]
                                  color: th.textMuted, // text-muted
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4), // mt-1
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14, // text-sm
                                fontWeight: FontWeight.w700, // font-bold
                                color: isCurrent
                                    ? th.accentSoft // text-accent-soft
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Правый блок: score или «Обзор».
                    Padding(
                      padding: const EdgeInsets.only(right: 8), // pr-2
                      child: item.localItem?.score != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2), // px-2.5 py-0.5
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(999), // rounded-full
                                border: Border.all(
                                    color: Colors.white.withAlpha(51)),
                                color: const Color(0xFF4A63C9), // score-bg
                              ),
                              child: Text(
                                '${item.localItem!.score}',
                                style: const TextStyle(
                                  fontSize: 12, // text-xs
                                  fontWeight: FontWeight.w900, // font-black
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : (!hasLocal && !isCurrent)
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4), // px-2.5 py-1
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(6), // rounded-md
                                    border: Border.all(
                                        color: Colors.white
                                            .withAlpha(21)), // /[0.08]
                                    color: Colors.white.withAlpha(13), // /5
                                  ),
                                  child: Text(
                                    t.tr('detail.overviewBadge'),
                                    style: TextStyle(
                                      fontSize: 12, // text-xs
                                      fontWeight: FontWeight.w500, // font-medium
                                      color: const Color(0xFFCBD5E1), // slate-300
                                    ),
                                  ),
                                )
                              : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
