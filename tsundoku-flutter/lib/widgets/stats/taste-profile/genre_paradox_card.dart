import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_label.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/stats/taste-profile/GenreParadoxCard.svelte`.
///
/// Карточка «Парадокс жанров»:
/// - Двойной горизонтальный прогресс-бар по каждому жанру:
///   1. Доля завершенных тайтлов (зелёный/emerald-400)
///   2. Доля брошенных тайтлов (розовый/rose-400)
/// - Название жанра с локализацией через `genreLabel`
/// - Проценты завершения и дропа справа
class GenreParadoxCard extends ConsumerWidget {
  final List<GenreCompletionStat> paradox;

  const GenreParadoxCard({
    super.key,
    required this.paradox,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

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
          // Шапка: весы + заголовок слева, легенда справа
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
                    LucideIcons.scale,
                    size: 16,
                    color: Color(0xFF38BDF8), // text-sky-400
                  ),
                  const SizedBox(width: 8), // gap-2
                  Text(
                    t.tr('stats.taste.paradoxTitle'),
                    style: const TextStyle(
                      fontSize: 16, // text-base
                      fontWeight: FontWeight.w600, // font-semibold
                      letterSpacing: -0.4, // tracking-tight
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, // size-2
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xE634D399), // bg-emerald-400/90
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6), // gap-1.5
                      Text(
                        t.tr('stats.taste.paradoxCompletion'),
                        style: const TextStyle(
                          fontSize: 11, // text-[11px]
                          color: Color(0xFF94A3B8), // text-slate-400
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12), // gap-3
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, // size-2
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xE6FB7185), // bg-rose-400/90
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6), // gap-1.5
                      Text(
                        t.tr('stats.taste.paradoxDrop'),
                        style: const TextStyle(
                          fontSize: 11, // text-[11px]
                          color: Color(0xFF94A3B8), // text-slate-400
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16), // mb-4

          if (paradox.isEmpty)
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
                for (int i = 0; i < paradox.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12), // space-y-3
                  _GenreParadoxRow(
                    stat: paradox[i],
                    label: genreLabel(paradox[i].genre, t, locale),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _GenreParadoxRow extends StatelessWidget {
  final GenreCompletionStat stat;
  final String label;

  const _GenreParadoxRow({
    required this.stat,
    required this.label,
  });

  static String _formatNum(num val) {
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 112, // w-28
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14, // text-sm
              fontWeight: FontWeight.w500, // font-medium
              color: Color(0xFFE2E8F0), // text-slate-200
            ),
          ),
        ),
        const SizedBox(width: 12), // gap-3
        Expanded(
          child: Column(
            children: [
              // Бар завершения (зелёный)
              ClipRRect(
                borderRadius: BorderRadius.circular(9999),
                child: Container(
                  height: 10, // h-2.5
                  width: double.infinity,
                  color: Colors.white.withAlpha(13), // bg-white/5
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (stat.completionRate / 100.0).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xE634D399), // bg-emerald-400/90
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4), // space-y-1
              // Бар дропа (розовый)
              ClipRRect(
                borderRadius: BorderRadius.circular(9999),
                child: Container(
                  height: 10, // h-2.5
                  width: double.infinity,
                  color: Colors.white.withAlpha(13), // bg-white/5
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (stat.dropRate / 100.0).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xE6FB7185), // bg-rose-400/90
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12), // gap-3
        SizedBox(
          width: 96, // w-24
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_formatNum(stat.completionRate)}%',
                style: const TextStyle(
                  fontSize: 11, // text-[11px]
                  height: 1.25, // leading-tight
                  color: Color(0xFF6EE7B7), // text-emerald-300
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '${_formatNum(stat.dropRate)}%',
                style: const TextStyle(
                  fontSize: 11, // text-[11px]
                  height: 1.25, // leading-tight
                  color: Color(0xFFFDA4AF), // text-rose-300
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
