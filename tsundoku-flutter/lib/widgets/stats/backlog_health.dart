/// Порт `mediatracker-ui/src/widgets/stats/BacklogHealth.svelte`.
///
/// Виджет баланса медиатеки (Индекс Цундоку):
/// - Иконка весов (Scale, emerald-400) + заголовок `stats.backlogTitle`;
/// - Сегментированный прогресс-бар (completed / inProgress / planned);
/// - Легенда со счётчиками статусов;
/// - Вердикт продуктивности / баланса / Цундоку / пустой медиатеки;
/// - Ссылка на ревизию заброшенных тайтлов (`staleTriage.triageActionLink`).
library;

import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class BacklogHealth extends ConsumerStatefulWidget {
  final AdvancedStats stats;
  final VoidCallback? onMediaChanged;
  final VoidCallback? onOpenStaleBacklog;

  const BacklogHealth({
    super.key,
    required this.stats,
    this.onMediaChanged,
    this.onOpenStaleBacklog,
  });

  @override
  ConsumerState<BacklogHealth> createState() => _BacklogHealthState();
}

class _BacklogHealthState extends ConsumerState<BacklogHealth> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final totalTitles = widget.stats.totalTitles;
    final completedTitles = widget.stats.completedTitles;
    final rawPlanned = widget.stats.plannedTitles;

    final plannedCount = rawPlanned != null
        ? math.max(0, rawPlanned)
        : math.max(0, totalTitles - completedTitles);

    final inProgressCount = rawPlanned != null
        ? math.max(0, totalTitles - completedTitles - plannedCount)
        : 0;

    final completedPercent =
        totalTitles > 0 ? (completedTitles / totalTitles) * 100 : 0.0;
    final plannedPercent =
        totalTitles > 0 ? (plannedCount / totalTitles) * 100 : 0.0;
    final inProgressPercent =
        totalTitles > 0 ? (inProgressCount / totalTitles) * 100 : 0.0;

    final String verdictText;
    if (widget.stats.totalTitles == 0) {
      verdictText = t.tr('stats.emptyVerdict');
    } else if (widget.stats.completionRatePercent >= 60) {
      verdictText = t.tr('stats.productiveVerdict');
    } else if (widget.stats.completionRatePercent >= 30) {
      verdictText = t.tr('stats.balancedVerdict');
    } else {
      verdictText = t.tr('stats.tsundokuVerdict');
    }

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
          // Шапка: Scale иконка + заголовок
          Row(
            children: [
              Icon(
                LucideIcons.scale,
                size: 16,
                color: const Color(0xFF34D399), // text-emerald-400
              ),
              const SizedBox(width: 8), // gap-2
              Expanded(
                child: Text(
                  t.tr('stats.backlogTitle'),
                  style: const TextStyle(
                    fontSize: 16, // text-base
                    fontWeight: FontWeight.w600, // font-semibold
                    letterSpacing: -0.2, // tracking-tight
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16), // mb-4

          // Сегментированный бар: h-3 w-full rounded-full bg-white/5
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: Container(
              height: 12, // h-3
              width: double.infinity,
              color: Colors.white.withAlpha(13), // bg-white/5
              child: totalTitles == 0
                  ? ColoredBox(
                      color: Colors.white.withAlpha(26), // bg-white/10
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final cPercent = completedPercent.clamp(0.0, 100.0);
                        final iPercent = inProgressPercent.clamp(0.0, 100.0);
                        final pPercent = plannedPercent.clamp(0.0, 100.0);

                        final cW = (w * (cPercent / 100)).clamp(0.0, w);
                        final iW = (w * (iPercent / 100)).clamp(0.0, w - cW);
                        final pW = (w * (pPercent / 100)).clamp(0.0, w - cW - iW);

                        return Row(
                          children: [
                            if (completedPercent > 0 && cW > 0)
                              SizedBox(
                                width: cW,
                                height: 12,
                                child: Tooltip(
                                  message: t.tf('stats.segmentTooltip', [
                                    t.tr('stats.completed'),
                                    completedTitles,
                                    completedPercent.round(),
                                  ]),
                                  child: ColoredBox(color: theme.chartEmerald),
                                ),
                              ),
                            if (inProgressPercent > 0 && iW > 0)
                              SizedBox(
                                width: iW,
                                height: 12,
                                child: Tooltip(
                                  message: t.tf('stats.segmentTooltip', [
                                    t.tr('stats.inProgress'),
                                    inProgressCount,
                                    inProgressPercent.round(),
                                  ]),
                                  child: ColoredBox(color: theme.chartViolet),
                                ),
                              ),
                            if (plannedPercent > 0 && pW > 0)
                              SizedBox(
                                width: pW,
                                height: 12,
                                child: Tooltip(
                                  message: t.tf('stats.segmentTooltip', [
                                    t.tr('stats.planned'),
                                    plannedCount,
                                    plannedPercent.round(),
                                  ]),
                                  child: ColoredBox(color: theme.chartBlue),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 14), // mt-3.5

          // Легенда со счётчиками
          Wrap(
            spacing: 16, // gap-4 sm:gap-6
            runSpacing: 8,
            children: [
              _LegendItem(
                color: theme.chartEmerald,
                label: t.tr('stats.completed'),
                count: completedTitles,
              ),
              _LegendItem(
                color: theme.chartViolet,
                label: t.tr('stats.inProgress'),
                count: inProgressCount,
              ),
              _LegendItem(
                color: theme.chartBlue,
                label: t.tr('stats.planned'),
                count: plannedCount,
              ),
            ],
          ),

          // Вердикт
          Container(
            margin: const EdgeInsets.only(top: 16), // mt-4
            padding: const EdgeInsets.all(14), // p-3.5
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5), // bg-white/[0.02]
              border: Border.all(color: Colors.white.withAlpha(13)), // border-white/5
              borderRadius: BorderRadius.circular(8), // rounded-lg
            ),
            child: Text(
              verdictText,
              style: const TextStyle(
                fontSize: 14, // text-sm
                height: 1.625, // leading-relaxed
                color: Color(0xFFCBD5E1), // text-slate-300
              ),
            ),
          ),

          // Ссылка на ревизию заброшенных тайтлов
          Padding(
            padding: const EdgeInsets.only(top: 12), // mt-3
            child: InkWell(
              onTap: widget.onOpenStaleBacklog,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Text(
                  t.tr('staleTriage.triageActionLink'),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: theme.accent, // text-accent
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

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, // size-2.5
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8), // gap-2
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12, // text-xs
            color: Color(0xFFCBD5E1), // text-slate-300
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600, // font-semibold
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
