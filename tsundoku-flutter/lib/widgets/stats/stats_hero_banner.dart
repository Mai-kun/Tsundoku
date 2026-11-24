/// Порт `mediatracker-ui/src/widgets/stats/StatsHeroBanner.svelte`.
///
/// Hero-секция статистики: заголовок с часами/тайтлами, подзаголовок с днями
/// и три карточки-метрики (стрик, средний балл, завершения).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// `new Intl.NumberFormat(locale)` — группировка разрядов (ru: пробелы,
/// en: запятые).
String formatStatsNumber(int value, Locale locale) {
  final digits = value.toString();
  final group = locale == Locale.ru ? ' ' : ',';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final posFromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(group);
  }
  return buffer.toString();
}

class StatsHeroBanner extends ConsumerWidget {
  final AdvancedStats stats;

  const StatsHeroBanner({super.key, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final th = TsundokuTheme.of(context);
    final hours = formatStatsNumber(stats.totalHours.round(), locale);
    final titles = formatStatsNumber(stats.totalTitles, locale);
    final days = formatStatsNumber(stats.totalDays.round(), locale);

    Widget metricCard({
      required IconData icon,
      required Color iconBg,
      required Color iconColor,
      required String label,
      required String value,
    }) =>
        Container(
          padding: const EdgeInsets.all(16), // p-4
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(color: Colors.white.withAlpha(13)), // white/5
            color: const Color(0xFF151A26), // bg-[#151a26]
          ),
          child: Row(
            children: [
              Container(
                width: 44, // h-11 w-11
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  color: iconBg,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14), // gap-3.5
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        fontWeight: FontWeight.w500,
                        color: th.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2), // mt-0.5
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16, // text-base
                        fontWeight: FontWeight.w700,
                        color: th.textPrimary, // text-ink
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSm = constraints.maxWidth >= 640;
        final columns = isSm ? 3 : 1; // sm:grid-cols-3
        final gap = 14.0; // gap-3.5
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tf('stats.heroTitle', [hours, titles]),
              style: TextStyle(
                fontSize: isSm ? 30 : 24, // text-2xl sm:text-3xl
                fontWeight: FontWeight.w800, // font-extrabold
                letterSpacing: isSm ? -0.75 : -0.6, // tracking-tight
                color: th.textPrimary, // text-ink
              ),
            ),
            const SizedBox(height: 4), // mt-1
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672), // max-w-2xl
              child: Text(
                t.tf('stats.heroSubtitle', [days]),
                style: TextStyle(
                  fontSize: isSm ? 16 : 14, // text-sm sm:text-base
                  color: th.textMuted, // text-muted
                ),
              ),
            ),
            const SizedBox(height: 16), // space-y-4
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: metricCard(
                    icon: LucideIcons.flame,
                    iconBg: const Color(0x1AF59E0B), // bg-amber-500/10
                    iconColor: const Color(0xFFF59E0B), // text-amber-500
                    label: t.tr('stats.activityStreak'),
                    value: t.tf('stats.streakDays', [stats.currentStreakDays]),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: metricCard(
                    icon: LucideIcons.star,
                    iconBg: const Color(0x1AEAB308), // bg-yellow-500/10
                    iconColor: const Color(0xFFFACC15), // text-yellow-400
                    label: t.tr('stats.averageScore'),
                    value:
                        '${stats.averageScore > 0 ? stats.averageScore : '—'} / 10',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: metricCard(
                    icon: LucideIcons.checkCircle,
                    iconBg: const Color(0x1A10B981), // bg-emerald-500/10
                    iconColor: const Color(0xFF34D399), // text-emerald-400
                    label: t.tr('stats.completed'),
                    value: () {
                      final rateStr = stats.completionRatePercent % 1 == 0
                          ? stats.completionRatePercent.toInt().toString()
                          : stats.completionRatePercent.toStringAsFixed(1);
                      return '${stats.completedTitles} / ${stats.totalTitles} ($rateStr%)';
                    }(),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
