/// Порт `mediatracker-ui/src/widgets/stats/MonthlyActivityChart.svelte`.
///
/// Столбчатый график завершений за 12 месяцев: иконка-заголовок, бейдж-итог,
/// колонки с scaleY-высотами и hover-тултипы, нулевые месяцы — плоская
/// плашка, подписи месяцев снизу.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// `{ monthYear: '2026-01', count: 5 }`.
typedef MonthlyCompletionItem = MonthCompletion;

class MonthlyActivityChart extends ConsumerWidget {
  final List<MonthlyCompletionItem> completions;

  const MonthlyActivityChart({super.key, this.completions = const []});

  String _formatMonth(String monthYear, Locale locale) {
    final date = DateTime.tryParse('$monthYear-01');
    if (date == null) return monthYear;
    initializeDateFormatting(locale.wire, null);
    return DateFormat('MMM', locale.wire).format(date);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final totalCompletions = completions.fold<int>(0, (s, c) => s + c.count);
    final maxCount = completions.fold<int>(0, (m, c) => c.count > m ? c.count : m);
    final maxEffective = maxCount < 1 ? 1 : maxCount;

    return Container(
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(13)), // white/5
        color: const Color(0xFF151A26), // bg-[#151a26]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.calendarDays,
                        size: 16, color: const Color(0xFF818CF8)),
                    const SizedBox(width: 8), // gap-2
                    Flexible(
                      child: Text(
                        t.tr('stats.monthlyActivity'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16, // text-base
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4), // px-2.5 py-1
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6), // rounded-md
                  border: Border.all(color: const Color(0x4D818CF8)),
                  color: const Color(0x26818CF8),
                ),
                child: Text(
                  t.tf('stats.completedInYear', [totalCompletions]),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF818CF8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16), // mb-4
          LayoutBuilder(builder: (context, constraints) {
            final available = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 340.0;
            final chartWidth =
                available < 340 ? 340.0 : available; // min-w-[340px]
            Widget chart = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 176, // h-44
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final c in completions)
                        Expanded(child: _MonthColumn(item: c, maxCount: maxEffective)),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Colors.white.withAlpha(13))), // border-t
                  ),
                  padding: const EdgeInsets.only(top: 8), // pt-2
                  child: Row(
                    children: [
                      for (final c in completions)
                        Expanded(
                          child: Text(
                            _formatMonth(c.monthYear, locale),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF94A3B8), // text-slate-400
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
            return chartWidth > available
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: 340, child: chart))
                : chart;
          }),
        ],
      ),
    );
  }
}

/// Один месяц: тултип (обёрнут в Tooltip), число, градиентная колонка или
/// нулевая плашка.
class _MonthColumn extends ConsumerWidget {
  final MonthlyCompletionItem item;
  final int maxCount;

  const _MonthColumn({required this.item, required this.maxCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final heightPercent = (item.count / maxCount) * 100;

    if (item.count > 0) {
      return Tooltip(
        message: _tooltip(item, t, locale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${item.count}',
              style: TextStyle(
                fontSize: 11, // text-[11px]
                fontWeight: FontWeight.w600,
                color: const Color(0xFFCBD5E1), // text-slate-300
                fontFeatures: const [
                  FontFeature.tabularFigures(), // tabular-nums
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: heightPercent / 100, // scaleY-аналог
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(6)), // rounded-t-md
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF818CF8), // to-[#818cf8]
                          TsundokuTheme.of(context).accentBright, // from-accent-bright
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
    // count == 0: h-[4px] плашка white/5.
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
          color: Colors.white.withAlpha(13),
        ),
      ),
    );
  }

  String _tooltip(MonthlyCompletionItem item, I18nDictionary t, Locale locale) {
    final date = DateTime.tryParse('${item.monthYear}-01');
    final formattedDate = date == null
        ? item.monthYear
        : DateFormat('MMM y', locale.wire).format(date);
    return '$formattedDate: ${t.tf('stats.completedTooltip', [item.count])}';
  }
}
