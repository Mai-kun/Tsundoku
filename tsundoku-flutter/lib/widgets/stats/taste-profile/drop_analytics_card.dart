import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/entities/media/model/drop_reasons.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/stats/taste-profile/DropAnalyticsCard.svelte`.
///
/// Карточка «Анатомия дропа»:
/// - Общий счетчик брошенных тайтлов
/// - Точка невозврата (средний процент прогресса при дропе)
/// - 3-цветный прогресс-бар (ранний <20%, в середине 20-70%, в шаге от финала >70%) с легендой
/// - Топ причин дропа с процентными барами
/// - Инсайт-цитата в зависимости от преобладающего паттерна дропа
class DropAnalyticsCard extends ConsumerWidget {
  final DropAnalytics analytics;

  const DropAnalyticsCard({
    super.key,
    required this.analytics,
  });

  static String _formatNum(num val) {
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  static String _getInsightText(DropAnalytics analytics, bool isRu) {
    if (analytics.totalDropped == 0) return '';
    if (analytics.earlyDropCount >= analytics.totalDropped * 0.5) {
      return isRu
          ? 'Вы не боитесь бросать скучное в самом начале — это экономит сотни часов жизни для действительно любимых историй.'
          : "You aren't afraid to drop boring titles early — saving hundreds of hours of life for stories you truly love.";
    }
    if (analytics.lateDropCount >= analytics.totalDropped * 0.4) {
      return isRu
          ? 'Вы даете произведениям шанс раскрыться до самого конца. Помните: дропать никогда не поздно, если история перестала приносить удовольствие.'
          : "You give stories a chance to unfold until the very end. Remember: it's never too late to drop something that stopped bringing joy.";
    }
    return isRu
        ? 'Вы тонко чувствуете момент, когда история перестает радовать, и освобождаете место для новых открытий.'
        : 'You have a keen sense of when a story stops resonating, freeing up time for new discoveries.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final isRu = locale == Locale.ru;

    final earlyShare = analytics.totalDropped > 0
        ? ((analytics.earlyDropCount / analytics.totalDropped) * 100).round()
        : 0;
    final midShare = analytics.totalDropped > 0
        ? ((analytics.midDropCount / analytics.totalDropped) * 100).round()
        : 0;
    final lateShare = analytics.totalDropped > 0
        ? math.max(0, 100 - earlyShare - midShare)
        : 0;

    final insightText = _getInsightText(analytics, isRu);

    final avgProgressNum = analytics.averageDropProgressPercent % 1 == 0
        ? analytics.averageDropProgressPercent.toInt()
        : analytics.averageDropProgressPercent;

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
          // Шапка
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.ban,
                    size: 16,
                    color: Color(0xFFFB7185), // text-rose-400
                  ),
                  const SizedBox(width: 8), // gap-2
                  Text(
                    t.tr('stats.taste.dropAnalytics.title'),
                    style: const TextStyle(
                      fontSize: 16, // text-base
                      fontWeight: FontWeight.w600, // font-semibold
                      letterSpacing: -0.2, // tracking-tight
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
                  t.tf('stats.taste.dropAnalytics.totalDropped',
                      [analytics.totalDropped]),
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

          if (analytics.totalDropped == 0) ...[
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(minHeight: 96), // min-h-24
              alignment: Alignment.center,
              child: Text(
                t.tr('stats.taste.dropAnalytics.empty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: theme.textSecondary, // text-muted
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            // Точка невозврата
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.tr('stats.taste.dropAnalytics.noReturnTitle')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        letterSpacing: 0.8, // tracking-wider
                        color: Color(0xFF94A3B8), // text-slate-400
                      ),
                    ),
                    Text(
                      'avg ${_formatNum(analytics.averageDropProgressPercent)}%',
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.bold, // font-bold
                        color: Color(0xFFE2E8F0), // text-slate-200
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t.tf('stats.taste.dropAnalytics.avgDropText', [avgProgressNum]),
                  style: const TextStyle(
                    fontSize: 14, // text-sm
                    height: 1.5, // leading-relaxed
                    color: Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
                const SizedBox(height: 10),

                // 3-цветный прогресс-бар
                ClipRRect(
                  borderRadius: BorderRadius.circular(9999), // rounded-full
                  child: Container(
                    height: 12, // h-3
                    width: double.infinity,
                    color: Colors.white.withAlpha(13), // bg-white/5
                    child: Row(
                      children: [
                        if (earlyShare > 0)
                          Expanded(
                            flex: earlyShare,
                            child: Tooltip(
                              message:
                                  '${t.tr('stats.taste.dropAnalytics.earlyDrop')}: ${analytics.earlyDropCount} ($earlyShare%)',
                              child: Container(
                                color: const Color(0xE634D399), // bg-emerald-400/90
                              ),
                            ),
                          ),
                        if (midShare > 0)
                          Expanded(
                            flex: midShare,
                            child: Tooltip(
                              message:
                                  '${t.tr('stats.taste.dropAnalytics.midDrop')}: ${analytics.midDropCount} ($midShare%)',
                              child: Container(
                                color: const Color(0xE6FBBF24), // bg-amber-400/90
                              ),
                            ),
                          ),
                        if (lateShare > 0)
                          Expanded(
                            flex: lateShare,
                            child: Tooltip(
                              message:
                                  '${t.tr('stats.taste.dropAnalytics.lateDrop')}: ${analytics.lateDropCount} ($lateShare%)',
                              child: Container(
                                color: const Color(0xE6FB7185), // bg-rose-400/90
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Легенда
                Wrap(
                  spacing: 16, // gap-x-4
                  runSpacing: 4, // gap-y-1
                  children: [
                    _LegendItem(
                      dotColor: const Color(0xE634D399),
                      label: t.tr('stats.taste.dropAnalytics.earlyDrop'),
                      count: analytics.earlyDropCount,
                    ),
                    _LegendItem(
                      dotColor: const Color(0xE6FBBF24),
                      label: t.tr('stats.taste.dropAnalytics.midDrop'),
                      count: analytics.midDropCount,
                    ),
                    _LegendItem(
                      dotColor: const Color(0xE6FB7185),
                      label: t.tr('stats.taste.dropAnalytics.lateDrop'),
                      count: analytics.lateDropCount,
                    ),
                  ],
                ),
              ],
            ),

            // Топ причин дропа
            if (analytics.topReasons.isNotEmpty) ...[
              const SizedBox(height: 24), // mt-6
              Container(
                padding: const EdgeInsets.only(top: 20), // pt-5
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withAlpha(13), // border-white/5
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('stats.taste.dropAnalytics.topReasonsTitle')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w600, // font-semibold
                        letterSpacing: 0.8, // tracking-wider
                        color: Color(0xFF94A3B8), // text-slate-400
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < analytics.topReasons.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10), // space-y-2.5
                      _DropReasonRow(
                        stat: analytics.topReasons[i],
                        lang: locale.wire,
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Инсайт-цитата
            if (insightText.isNotEmpty) ...[
              const SizedBox(height: 20), // mt-5
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
                  insightText,
                  style: const TextStyle(
                    fontSize: 14, // text-sm
                    height: 1.5, // leading-relaxed
                    color: Color(0xE66EE7B7), // text-emerald-300/90
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color dotColor;
  final String label;
  final int count;

  const _LegendItem({
    required this.dotColor,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, // size-2
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6), // gap-1.5
        Text(
          label,
          style: const TextStyle(
            fontSize: 12, // text-xs
            color: Color(0xFF94A3B8), // text-slate-400
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DropReasonRow extends StatelessWidget {
  final DropReasonStat stat;
  final String lang;

  const _DropReasonRow({
    required this.stat,
    required this.lang,
  });

  static String _formatNum(num val) {
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final label = getDropReasonLabel(stat.reason, lang: lang);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: Color(0xFFE2E8F0), // text-slate-200
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${stat.count} ',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE2E8F0),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '(${_formatNum(stat.percentage)}%)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4), // space-y-1
        ClipRRect(
          borderRadius: BorderRadius.circular(9999), // rounded-full
          child: Container(
            height: 8, // h-2
            width: double.infinity,
            color: Colors.white.withAlpha(13), // bg-white/5
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (stat.percentage / 100.0).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xCCFB7185), // bg-rose-400/80
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
