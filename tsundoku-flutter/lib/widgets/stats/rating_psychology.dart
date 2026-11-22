/// Порт `mediatracker-ui/src/widgets/stats/RatingPsychology.svelte`.
///
/// Виджет психологии оценок:
/// - Заголовок `stats.ratingPsychology` + средний балл `stats.averagePrefix: X ★`;
/// - Список распределения оценок 1..10 (amber-400 звёзды, градиентные бары, счётчики);
/// - Средний балл по категориям (игры, фильмы, сериалы, аниме, книги, манга).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class RatingPsychology extends ConsumerWidget {
  final AdvancedStats stats;

  const RatingPsychology({super.key, required this.stats});

  static const List<int> _scores = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final typeLabels = <String, String>{
      'game': t.tr('stats.games'),
      'movie': t.tr('stats.movies'),
      'series': t.tr('stats.series'),
      'anime': t.tr('stats.anime'),
      'book': t.tr('stats.books'),
      'manga': t.tr('stats.manga'),
    };

    final distribution = _scores.map((score) {
      final count = (stats.scoreDistribution[score] ?? 0.0).round();
      return (score: score, count: count);
    }).toList();

    var maxCount = 1;
    for (final item in distribution) {
      if (item.count > maxCount) {
        maxCount = item.count;
      }
    }

    final typeScores = stats.averageScoreByType.entries
        .where((e) => e.value > 0)
        .map((e) => (label: typeLabels[e.key] ?? e.key, score: e.value))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Заголовок и средняя общая оценка
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t.tr('stats.ratingPsychology'),
              style: TextStyle(
                fontSize: 16, // text-base
                fontWeight: FontWeight.w600, // font-semibold
                letterSpacing: -0.4, // tracking-tight
                color: theme.textPrimary, // text-ink
              ),
            ),
            if (stats.averageScore > 0)
              Text(
                '${t.tr('stats.averagePrefix')}: ${stats.averageScore} ★',
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: Color(0xE6FBBF24), // text-amber-400/90
                ),
              ),
          ],
        ),
        const SizedBox(height: 16), // space-y-4

        // Список распределения оценок 1..10
        Semantics(
          label: t.tr('stats.ratingDistribution'),
          child: Column(
            children: [
              for (int i = 0; i < distribution.length; i++) ...[
                if (i > 0) const SizedBox(height: 6), // space-y-1.5
                _DistributionRow(
                  score: distribution[i].score,
                  count: distribution[i].count,
                  maxCount: maxCount,
                  textSecondary: theme.textSecondary,
                ),
              ],
            ],
          ),
        ),

        // Средний балл по категориям
        if (typeScores.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withAlpha(10)), // border-white/[0.04]
              ),
            ),
            padding: const EdgeInsets.only(top: 8), // pt-2
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tr('stats.averageByCategory').toUpperCase(),
                  style: TextStyle(
                    fontSize: 11, // text-[11px]
                    fontWeight: FontWeight.w500, // font-medium
                    letterSpacing: 1.0, // tracking-wider
                    color: theme.textSecondary, // text-muted
                  ),
                ),
                const SizedBox(height: 8), // mb-2
                Wrap(
                  spacing: 8, // gap-2
                  runSpacing: 8,
                  children: [
                    for (final item in typeScores)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ), // px-2.5 py-1
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6), // rounded-md
                          border: Border.all(
                            color: const Color(0x26F59E0B), // border-amber-500/15
                          ),
                          color: const Color(0x0DF59E0B), // bg-amber-500/5
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${item.label}: ',
                              style: const TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w500, // font-medium
                                color: Color(0xFFFCD34D), // text-amber-300
                              ),
                            ),
                            Text(
                              '${item.score} ★',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700, // font-bold
                                color: Color(0xFFFCD34D),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DistributionRow extends StatelessWidget {
  final int score;
  final int count;
  final int maxCount;
  final Color textSecondary;

  const _DistributionRow({
    required this.score,
    required this.count,
    required this.maxCount,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final pct = maxCount > 0 ? (count / maxCount) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 32, // w-8
          child: Text(
            '$score ★',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w600, // font-semibold
              color: Color(0xFFFBBF24), // text-amber-400
            ),
          ),
        ),
        const SizedBox(width: 10), // gap-2.5
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9999), // rounded-full
            child: Container(
              height: 12, // h-3
              color: Colors.white.withAlpha(10), // bg-white/[0.04]
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct.clamp(0.0, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(9999)),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xB3F59E0B), // from-amber-500/70
                        Color(0xFFFBBF24), // to-amber-400
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10), // gap-2.5
        SizedBox(
          width: 28, // w-7
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w500, // font-medium
              color: textSecondary, // text-muted
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
