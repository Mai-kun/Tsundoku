/// Порт `mediatracker-ui/src/widgets/stats/TimeDistributionDonut.svelte`.
///
/// Кольцевая диаграмма распределения времени по категориям:
/// - Donut SVG → `CustomPainter` (радиус 70, stroke-width 20, старт -90°);
/// - По центру кольца: общее время `stats.totalHours` + `stats.totalTime`;
/// - Сетка карточек по 6 категориям (игры, сериалы, фильмы, аниме, книги, манга);
/// - Подписи часов, процентов и доп. счётчики (серии, страницы, главы).
library;

import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/stats_hero_banner.dart';

class TimeDistributionDonut extends ConsumerWidget {
  final AdvancedStats stats;

  const TimeDistributionDonut({super.key, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final categories = [
      (
        id: 'game',
        label: t.tr('stats.games'),
        hours: stats.gameHours,
        color: theme.chartIndigo,
        extraText: null,
      ),
      (
        id: 'series',
        label: t.tr('stats.series'),
        hours: stats.seriesHours,
        color: theme.chartCyan,
        extraText:
            '${formatStatsNumber(stats.seriesEpisodesWatched ?? stats.totalEpisodesWatched, locale)} ${t.tr('stats.episodesShort')}',
      ),
      (
        id: 'movie',
        label: t.tr('stats.movies'),
        hours: stats.movieHours,
        color: theme.chartBlue,
        extraText: null,
      ),
      (
        id: 'anime',
        label: t.tr('stats.anime'),
        hours: stats.animeHours,
        color: theme.chartPurple,
        extraText:
            '${formatStatsNumber(stats.animeEpisodesWatched ?? stats.totalEpisodesWatched, locale)} ${t.tr('stats.episodesShort')}',
      ),
      (
        id: 'book',
        label: t.tr('stats.books'),
        hours: stats.bookHours,
        color: theme.chartAmber,
        extraText:
            '${formatStatsNumber(stats.totalPagesRead, locale)} ${t.tr('stats.pagesShort')}',
      ),
      (
        id: 'manga',
        label: t.tr('stats.manga'),
        hours: stats.mangaHours,
        color: theme.chartEmerald,
        extraText:
            '${formatStatsNumber(stats.totalChaptersRead, locale)} ${t.tr('stats.chaptersShort')}',
      ),
    ];

    final totalCalculatedHours = categories.fold<double>(
      0.0,
      (acc, cat) => acc + cat.hours,
    );

    final segments = totalCalculatedHours <= 0
        ? const <({Color color, double ratio})>[]
        : categories
            .where((c) => c.hours > 0)
            .map((c) => (
                  color: c.color,
                  ratio: c.hours / totalCalculatedHours,
                ))
            .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isRow = constraints.maxWidth >= 480;
        final isTwoCols = constraints.maxWidth >= 320 ||
            MediaQuery.sizeOf(context).width >= 640;

        Widget buildCategoryCard(
          ({
            String id,
            String label,
            double hours,
            Color color,
            String? extraText,
          }) cat,
        ) {
          final pct = totalCalculatedHours > 0
              ? (cat.hours / totalCalculatedHours * 100).round()
              : 0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // p-2 px-3
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5), // bg-white/[0.02]
              border: Border.all(
                color: Colors.white.withAlpha(8), // border-white/[0.03]
              ),
              borderRadius: BorderRadius.circular(8), // rounded-lg
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 10, // h-2.5 w-2.5
                        height: 10,
                        decoration: BoxDecoration(
                          color: cat.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10), // gap-2.5
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cat.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w500, // font-medium
                                color: theme.textPrimary, // text-ink
                              ),
                            ),
                            if (cat.extraText != null)
                              Text(
                                cat.extraText!,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11, // text-[11px]
                                  color: theme.textSecondary, // text-muted
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${formatStatsNumber(cat.hours.round(), locale)} ${t.tr('stats.hoursShort')}',
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        color: theme.textPrimary, // text-ink
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 11, // text-[11px]
                        color: theme.textSecondary, // text-muted
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget buildCardsGrid() {
          if (isTwoCols) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < categories.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 10), // gap-2.5
                  Row(
                    children: [
                      Expanded(child: buildCategoryCard(categories[i])),
                      const SizedBox(width: 10),
                      if (i + 1 < categories.length)
                        Expanded(child: buildCategoryCard(categories[i + 1]))
                      else
                        const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ],
              ],
            );
          } else {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < categories.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10), // gap-2.5
                  buildCategoryCard(categories[i]),
                ],
              ],
            );
          }
        }

        final donutWidget = SizedBox(
          width: 192, // w-48
          height: 192, // h-48
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CustomPaint(
                  painter: _DonutPainter(segments: segments),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${formatStatsNumber(stats.totalHours.round(), locale)} ${t.tr('stats.hoursShort')}',
                    style: TextStyle(
                      fontSize: 24, // text-2xl
                      fontWeight: FontWeight.w900, // font-black
                      letterSpacing: -0.5, // tracking-tight
                      color: theme.textPrimary, // text-ink
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    t.tr('stats.totalTime'),
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w500, // font-medium
                      color: theme.textSecondary, // text-muted
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        if (isRow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              donutWidget,
              const SizedBox(width: 24), // gap-6
              Expanded(child: buildCardsGrid()),
            ],
          );
        } else {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              donutWidget,
              const SizedBox(height: 24), // gap-6
              buildCardsGrid(),
            ],
          );
        }
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<({Color color, double ratio})> segments;

  const _DonutPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 180.0;
    final radius = 70.0 * scale;
    final strokeWidth = 20.0 * scale;

    if (segments.isEmpty) {
      final emptyPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0 * scale
        ..color = Colors.white.withAlpha(26); // text-white/10
      canvas.drawCircle(center, radius, emptyPaint);
      return;
    }

    var startAngle = -math.pi / 2; // -90 deg
    for (final seg in segments) {
      final sweepAngle = seg.ratio * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = seg.color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    if (oldDelegate.segments.length != segments.length) return true;
    for (var i = 0; i < segments.length; i++) {
      if (oldDelegate.segments[i] != segments[i]) return true;
    }
    return false;
  }
}
