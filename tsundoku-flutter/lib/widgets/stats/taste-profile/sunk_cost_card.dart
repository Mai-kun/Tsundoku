import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/stats/taste-profile/SunkCostCard.svelte`.
///
/// Карточка «Синдром потерянного времени»:
/// - Доля времени, потраченного на непонравившиеся или брошенные произведения
/// - Количество тайтлов в убыточной зоне
/// - Сегментированный бар распределения часов по категориям медиа
/// - Легенда со счётчиками часов
/// - Мотивирующий совет бросать то, что не радует
class SunkCostCard extends ConsumerWidget {
  final SunkCost sunkCost;

  const SunkCostCard({
    super.key,
    required this.sunkCost,
  });

  static Color _getCategoryColor(String type, TsundokuTheme theme) {
    switch (type) {
      case 'game':
        return theme.chartRose;
      case 'movie':
        return theme.chartOrange;
      case 'series':
        return theme.chartAmber;
      case 'anime':
        return theme.chartYellow;
      case 'book':
        return theme.chartLime;
      case 'manga':
        return theme.chartGreen;
      default:
        return theme.chartRose;
    }
  }

  static String _categoryLabel(I18nDictionary t, String type) {
    const known = {'all', 'anime', 'book', 'game', 'manga', 'movie', 'series'};
    if (known.contains(type)) {
      return t.tr('stats.genreCategories.$type');
    }
    return t.tr('stats.taste.sunkCostOther');
  }

  static String _formatPercentage(double percent) {
    return percent % 1 == 0
        ? percent.toInt().toString()
        : percent.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final breakdown = sunkCost.categoryBreakdown.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final hoursStr = sunkCost.lowScoreHours.round().toString();
    final percentStr = _formatPercentage(sunkCost.percentageOfTotal);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151A26), // bg-[#151a26]
        border: Border.all(color: Colors.white.withAlpha(13)), // border-white/5
        borderRadius: BorderRadius.circular(12), // rounded-xl
      ),
      padding: const EdgeInsets.all(20), // p-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Шапка: песочные часы + заголовок слева, процентный бейдж справа
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8, // gap-2
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.hourglass,
                    size: 16,
                    color: Color(0xFFFB7185), // text-rose-400
                  ),
                  const SizedBox(width: 8), // gap-2
                  Text(
                    t.tr('stats.taste.sunkCostTitle'),
                    style: const TextStyle(
                      fontSize: 16, // text-base
                      fontWeight: FontWeight.w600, // font-semibold
                      letterSpacing: -0.4, // tracking-tight
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ), // px-2.5 py-0.5
                decoration: BoxDecoration(
                  color: const Color(0x1AF43F5E), // bg-rose-500/10
                  border: Border.all(
                    color: const Color(0x33F43F5E), // border-rose-500/20
                  ),
                  borderRadius: BorderRadius.circular(9999), // rounded-full
                ),
                child: Text(
                  '${_formatPercentage(sunkCost.percentageOfTotal)}%',
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.bold, // font-bold
                    color: Color(0xFFFDA4AF), // text-rose-300
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12), // mb-3

          // Текст сообщения о потерянном времени
          Text(
            t.tf('stats.taste.sunkCostMessage', [hoursStr, percentStr]),
            style: const TextStyle(
              fontSize: 14, // text-sm
              height: 1.625, // leading-relaxed
              color: Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
          const SizedBox(height: 12), // mt-3

          // Плашка с количеством тайтлов в убыточной зоне
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ), // px-2 py-0.5
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13), // bg-white/5
              borderRadius: BorderRadius.circular(4), // rounded
            ),
            child: Text(
              t.tf('stats.taste.sunkCostTitlesCount', [sunkCost.titlesCount]),
              style: const TextStyle(
                fontSize: 12, // text-xs
                color: Color(0xFF94A3B8), // text-slate-400
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),

          // Сегментированный бар категорий + легенда
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 16), // mt-4
            ClipRRect(
              borderRadius: BorderRadius.circular(9999), // rounded-full
              child: Container(
                height: 12, // h-3
                width: double.infinity,
                color: Colors.white.withAlpha(13), // bg-white/5
                child: Row(
                  children: [
                    for (final entry in breakdown)
                      Expanded(
                        flex: (entry.value * 1000).round(),
                        child: Tooltip(
                          message:
                              '${_categoryLabel(t, entry.key)}: ${entry.value.round()} ${t.tr('stats.hoursShort')}',
                          child: Container(
                            color: _getCategoryColor(entry.key, theme),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8), // mt-2

            // Легенда
            Wrap(
              spacing: 16, // gap-x-4
              runSpacing: 4, // gap-y-1
              children: [
                for (final entry in breakdown)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, // size-2
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getCategoryColor(entry.key, theme),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6), // gap-1.5
                      Text(
                        _categoryLabel(t, entry.key),
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          color: Color(0xFF94A3B8), // text-slate-400
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${entry.value.round()} ${t.tr('stats.hoursShort')}',
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          color: Color(0xFF64748B), // text-slate-500
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],

          // Совет
          const SizedBox(height: 16), // mt-4
          Container(
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Color(0x6610B981), // border-emerald-500/40
                  width: 2, // border-l-2
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 12), // pl-3
            child: Text(
              t.tr('stats.taste.sunkCostAdvice'),
              style: const TextStyle(
                fontSize: 14, // text-sm
                height: 1.625, // leading-relaxed
                color: Color(0xE66EE7B7), // text-emerald-300/90
              ),
            ),
          ),
        ],
      ),
    );
  }
}
