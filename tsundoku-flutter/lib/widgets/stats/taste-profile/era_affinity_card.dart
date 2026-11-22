import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/stats/taste-profile/EraAffinityCard.svelte`.
///
/// Карточка «Золотая эпоха»:
/// - Десятилетия любимых произведений пользователя (оценка 8+ или завершенные)
/// - Горизонтальные прогресс-бары с чередующимися цветами (accent / #818cf8)
/// - Лейблы эпох (1980-е, 1990-е, 2000-е, 2010-е, 2020-е, До 1980-х)
/// - Количество тайтлов и процентная доля
class EraAffinityCard extends ConsumerWidget {
  final List<EraAffinityStat> eras;

  const EraAffinityCard({
    super.key,
    required this.eras,
  });

  static String _eraLabel(I18nDictionary t, String era) {
    const knownEras = {
      '1980s',
      '1990s',
      '2000s',
      '2010s',
      '2020s',
      'pre-1980',
    };
    if (knownEras.contains(era)) {
      return t.tr('stats.taste.eras.$era');
    }
    return era;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final maxPercentage = eras.isNotEmpty
        ? math.max(
            eras.map((era) => era.percentage).reduce(math.max),
            0.01,
          )
        : 1.0;

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
          // Шапка: иконка + заголовок
          Row(
            children: [
              const Icon(
                LucideIcons.crown,
                size: 16,
                color: Color(0xFFFBBF24), // text-amber-400
              ),
              const SizedBox(width: 8), // gap-2
              Text(
                t.tr('stats.taste.eraTitle'),
                style: const TextStyle(
                  fontSize: 16, // text-base
                  fontWeight: FontWeight.w600, // font-semibold
                  letterSpacing: -0.2, // tracking-tight
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4), // mb-1
          Text(
            t.tr('stats.taste.eraHint'),
            style: const TextStyle(
              fontSize: 12, // text-xs
              color: Color(0xFF94A3B8), // text-slate-400
            ),
          ),
          const SizedBox(height: 16), // mb-4

          if (eras.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 96), // min-h-24
              alignment: Alignment.center,
              child: Text(
                t.tr('stats.taste.emptyData'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: theme.textSecondary, // text-muted
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < eras.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12), // space-y-3
                  _EraRow(
                    stat: eras[i],
                    maxPercentage: maxPercentage,
                    label: _eraLabel(t, eras[i].era),
                    barColor:
                        i % 2 == 0 ? theme.accent : const Color(0xFF818CF8),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _EraRow extends StatelessWidget {
  final EraAffinityStat stat;
  final double maxPercentage;
  final String label;
  final Color barColor;

  const _EraRow({
    required this.stat,
    required this.maxPercentage,
    required this.label,
    required this.barColor,
  });

  static String _formatNum(num val) {
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final factor = maxPercentage > 0
        ? (stat.percentage / maxPercentage).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 96, // w-24
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14, // text-sm
              fontWeight: FontWeight.w500, // font-medium
              color: Color(0xFFE2E8F0), // text-slate-200
            ),
          ),
        ),
        const SizedBox(width: 12), // gap-3
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9999), // rounded-full
            child: Container(
              height: 10, // h-2.5
              color: Colors.white.withAlpha(13), // bg-white/5
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12), // gap-3
        SizedBox(
          width: 96, // w-24
          child: Text(
            '${stat.count} · ${_formatNum(stat.percentage)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12, // text-xs
              color: Color(0xFF94A3B8), // text-slate-400
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
