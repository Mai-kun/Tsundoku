/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/DetailHeader.svelte`.
///
/// Шапка детальной карточки: заголовок + оригинальное название, теги-бейджи,
/// рейтинги-источники (front face — источник+score, hover face — голоса),
/// Panel с синопсисом (раскрытие через AnimatedSize, кнопки перевода).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/i18n/index.dart';
import '../../entities/media/model/media_labels.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/ui/badge.dart';
import '../../shared/ui/button.dart';
import '../../shared/ui/panel.dart';

/// 1317 → «1.3k»; бейджу не хватает ни цифр, ни слов.
String formatVotes(num votes) {
  if (votes >= 1000) return '${(votes / 1000).toStringAsFixed(1)}k';
  return '${votes.round()}';
}

/// Рейтинг-источник (Svelte-интерфейс RatingBadge).
class RatingBadge {
  final String source;
  final double? score;
  final int? votes;

  const RatingBadge({required this.source, required this.score, this.votes});
}

class DetailHeader extends ConsumerWidget {
  final String title;

  /// Romaji / original title; null for types that do not carry one.
  final String? originalTitle;
  final List<String> tags;
  final List<RatingBadge> ratings;
  final String? synopsisText;
  final bool synopsisExpanded;
  final bool synopsisExpandable;
  final bool synopsisTranslated;
  final String? translatedSynopsis;
  final bool translatingSynopsis;
  final VoidCallback onToggleTranslate;
  final VoidCallback onToggleExpand;

  const DetailHeader({
    super.key,
    required this.title,
    required this.originalTitle,
    required this.tags,
    required this.ratings,
    required this.synopsisText,
    required this.synopsisExpanded,
    required this.synopsisExpandable,
    required this.synopsisTranslated,
    required this.translatedSynopsis,
    required this.translatingSynopsis,
    required this.onToggleTranslate,
    required this.onToggleExpand,
  });

  /// Имя источника (аналог веток Svelte; inline-SVG AniList рендерит
  /// [_AniListMark], неизвестный источник — [_StarFallback]).
  String _sourceLabel(String src) {
    if (src.contains('anilist')) return 'AniList';
    if (src.contains('shikimori')) return 'Shikimori';
    if (src.contains('mangadex')) return 'MangaDex';
    if (src.contains('myanimelist') || src.contains('jikan') || src.contains('mal')) {
      return 'MAL';
    }
    if (src.contains('tmdb')) return 'TMDB';
    if (src.contains('rawg')) return 'RAWG';
    if (src.contains('steam')) return 'Steam';
    if (src.contains('igdb')) return 'IGDB';
    if (src.contains('kitsu')) return 'Kitsu';
    if (src.contains('simkl')) return 'Simkl';
    if (src.contains('kinopoisk')) return 'Кинопоиск';
    if (src.contains('imdb')) return 'IMDb';
    if (src.contains('thetvdb') || src.contains('tvdb')) return 'TVDB';
    if (src.contains('mangaupdate')) return 'MangaUpdates';
    if (src.contains('openlibrary')) return 'OpenLibrary';
    return '';
  }

  /// Цвет бейджа источника (sourceBadgeClasses из mediaLabels).
  SourceBadgeColors _sourceColors(String src) => sourceBadgeClasses(src);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    final visibleRatings = ratings
        .where((r) => !RegExp(r'offline|офлайн', caseSensitive: false).hasMatch(r.source))
        .toList();

    final hasSynopsis = synopsisText != null && synopsisText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header > h1.mt-1: title + originalTitle.
        Padding(
          padding: const EdgeInsets.only(top: 4), // mt-1
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 30, // text-3xl
              fontWeight: FontWeight.w800, // font-extrabold
              letterSpacing: -0.75, // tracking-tight
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),
        if (originalTitle != null && originalTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6), // mt-1.5
            child: Text(
              originalTitle!,
              style: TextStyle(
                fontSize: 14, // text-sm
                fontWeight: FontWeight.w500, // font-medium
                color: th.textMuted, // text-muted
              ),
            ),
          ),
        const SizedBox(height: 8),
        // ul.flex.flex-wrap.gap-2 — теги-бейджи (rounded-full px-3 py-1).
        Wrap(
          spacing: 8, // gap-2
          runSpacing: 8,
          children: [
            for (final tag in tags)
              TsundokuBadge(
                tone: BadgeTone.accent,
                size: BadgeSize.sm,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                borderRadius: 999, // rounded-full
                child: Text(tag),
              ),
          ],
        ),
        const SizedBox(height: 10), // gap-2.5 → блок рейтингов ниже
        // div.flex.flex-wrap.items-center.gap-2.5 — рейтинги-источники.
        Wrap(
          spacing: 10, // gap-2.5
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center, // items-center
          children: [
            for (final rating in visibleRatings)
              _RatingBadgeWidget(
                rating: rating,
                sourceLabel: _sourceLabel(rating.source.toLowerCase()),
                colors: _sourceColors(rating.source.toLowerCase()),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Panel.space-y-2 с синопсисом.
        TsundokuPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.tr('detail.synopsisTitle').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w700, // font-bold
                        letterSpacing: 0.6, // tracking-wider
                        color: Color(0xFFCBD5E1), // text-slate-300
                      ),
                    ),
                  ),
                  if (hasSynopsis)
                    TsundokuButton(
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.xs,
                      loading: translatingSynopsis,
                      disabled: translatingSynopsis,
                      onPressed: onToggleTranslate,
                      child: Text(
                        translatingSynopsis
                            ? t.tr('detail.translating')
                            : synopsisTranslated
                                ? t.tr('detail.showOriginal')
                                : t.tr('detail.translate'),
                        style: TextStyle(color: th.accentSoft),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8), // space-y-2
              if (hasSynopsis) ...[
                _SynopsisText(
                  text: synopsisTranslated && translatedSynopsis != null
                      ? translatedSynopsis!
                      : synopsisText!,
                  expanded: synopsisExpanded,
                  expandable: synopsisExpandable,
                  th: th,
                ),
                const SizedBox(height: 8), // space-y-2
                if (synopsisExpandable)
                  GestureDetector(
                    onTap: onToggleExpand,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4), // pt-1
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            synopsisExpanded
                                ? t.tr('detail.collapse')
                                : t.tr('detail.readMore'),
                            style: TextStyle(
                                color: th.accentSoft, fontSize: 12),
                          ),
                          AnimatedRotation(
                            turns: synopsisExpanded ? 0.5 : 0,
                            duration:
                                const Duration(milliseconds: 150), // transition
                            child: Icon(LucideIcons.chevronDown,
                                size: 14, color: th.accentSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else
                Text(
                  t.tr('detail.noSynopsis'),
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    color: th.textMuted, // text-muted
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Синопсис: clamp 4 строки (collapsed) + градиент-хвост, раскрытие через
/// AnimatedSize (grid-rows 0fr→1fr из Svelte).
class _SynopsisText extends StatelessWidget {
  final String text;
  final bool expanded;
  final bool expandable;
  final TsundokuTheme th;

  const _SynopsisText({
    required this.text,
    required this.expanded,
    required this.expandable,
    required this.th,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200), // transition-[height] 200ms
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Stack(
        children: [
          Text(
            text,
            maxLines: expandable && !expanded ? 4 : null, // COLLAPSED_LINES = 4
            overflow: expandable && !expanded
                ? TextOverflow.ellipsis
                : TextOverflow.visible,
            style: TextStyle(
              fontSize: 14, // text-sm
              height: 1.625, // leading-relaxed
              color: th.textSecondary, // text-[var(--color-ink-dim)]
            ),
          ),
          // Хвост-градиент при свернутом состоянии (transition-opacity 200ms).
          if (expandable && !expanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 48, // h-12
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          th.bgSurface, // --color-panel-line → --bg-surface
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Рейтинг-бейдж: front face (источник+score) / hover face (голоса).
class _RatingBadgeWidget extends StatefulWidget {
  final RatingBadge rating;
  final String sourceLabel;
  final SourceBadgeColors colors;

  const _RatingBadgeWidget({
    required this.rating,
    required this.sourceLabel,
    required this.colors,
  });

  @override
  State<_RatingBadgeWidget> createState() => _RatingBadgeWidgetState();
}

class _RatingBadgeWidgetState extends State<_RatingBadgeWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final rating = widget.rating;
    final hasVotes = (rating.votes ?? 0) > 0;
    final hasScore = rating.score != null && rating.score! > 0;
    final known = widget.sourceLabel.isNotEmpty;
    final label = known ? widget.sourceLabel : rating.source;
    final src = rating.source.toLowerCase();
    final scoreText = hasScore ? rating.score!.toStringAsFixed(1) : '—';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        label:
            '${rating.source}: $scoreText${hasVotes ? ' (${rating.votes})' : ''}',
        child: Container(
          height: 36, // h-9
          padding: const EdgeInsets.symmetric(horizontal: 12), // px-3
          decoration: BoxDecoration(
            color: widget.colors.background,
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(color: widget.colors.border),
            boxShadow: const [
              // shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05)
              BoxShadow(
                color: Color(0x0D000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Front face: source + score (уезжает вверх и тает при hover).
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _hovered && hasVotes ? 0 : 1,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 200),
                  offset: _hovered && hasVotes
                      ? const Offset(0, -1 / 6) // -translate-y-1.5 @ h-9
                      : Offset.zero,
                  child: SizedBox(
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (src.contains('anilist')) ...[
                          _AniListMark(color: widget.colors.text),
                          const SizedBox(width: 6), // gap-1.5
                        ],
                        if (!known) ...[
                          // Неизвестный источник: Star + сырое имя (#26 —
                          // шрифт-иконка без fill).
                          Icon(LucideIcons.star,
                              size: 13, color: widget.colors.text),
                          const SizedBox(width: 6), // gap-1.5
                        ],
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11, // text-[11px]
                            fontWeight: FontWeight.w900, // font-black
                            letterSpacing: 0.66, // tracking-wider
                            color: widget.colors.text,
                          ),
                        ),
                        const SizedBox(width: 8), // gap-2
                        Text(
                          scoreText,
                          style: TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: hasScore
                                ? FontWeight.w800 // font-extrabold
                                : FontWeight.w500, // font-medium
                            color: hasScore
                                ? Colors.white
                                : Colors.white
                                    .withAlpha(102), // text-white/40
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Hover face: голоса (заезжает снизу при hover).
              if (hasVotes)
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _hovered ? 1 : 0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 200),
                      offset: _hovered ? Offset.zero : const Offset(0, 1),
                      child: Container(
                        height: 36,
                        color: Colors.black.withAlpha(115), // bg-black/45
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(LucideIcons.users,
                                size: 11, color: Colors.white),
                            const SizedBox(width: 4), // gap-1
                            Text(
                              formatVotes(rating.votes ?? 0),
                              style: const TextStyle(
                                fontSize: 11, // text-[11px]
                                fontWeight: FontWeight.w600, // font-semibold
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
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

/// Inline-SVG AniList-марки из Svelte (viewBox 0 0 24 24, fill currentColor):
/// точный путь 1-в-1, масштаб 14/24.
class _AniListMark extends StatelessWidget {
  final Color color;

  const _AniListMark({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size.square(14), painter: _AniListPainter(color));
  }
}

class _AniListPainter extends CustomPainter {
  final Color color;

  _AniListPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final path = Path()
      // M24 17.561v4.425H13.678v-4.425z
      ..moveTo(24, 17.561)
      ..lineTo(24, 21.986)
      ..lineTo(13.678, 21.986)
      ..lineTo(13.678, 17.561)
      ..close()
      // M12.924 2.014l7.157 15.547H14.88l-1.393-3.088H8.847l-1.385 3.088H2.179
      // L9.345 2.014h3.579z
      ..moveTo(12.924, 2.014)
      ..lineTo(20.081, 17.561)
      ..lineTo(14.88, 17.561)
      ..lineTo(13.487, 14.473)
      ..lineTo(8.847, 14.473)
      ..lineTo(7.462, 17.561)
      ..lineTo(2.179, 17.561)
      ..lineTo(9.345, 2.014)
      ..lineTo(12.924, 2.014)
      ..close()
      // m-.897 8.358L10.37 6.452l-1.65 3.92h3.307z (от старта 2-го субпути)
      ..moveTo(12.027, 10.372)
      ..lineTo(10.37, 6.452)
      ..lineTo(8.72, 10.372)
      ..lineTo(12.027, 10.372)
      ..close();
    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AniListPainter oldDelegate) => oldDelegate.color != color;
}
