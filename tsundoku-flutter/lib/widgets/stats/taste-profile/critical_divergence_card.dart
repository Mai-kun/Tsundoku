import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/stats/taste-profile/CriticalDivergenceCard.svelte`.
///
/// Карточка «Я против всего мира»: расхождение оценок пользователя с мировой оценкой.
/// Отображает скрытый шедевр (пользователь > мир) и главное разочарование (мир > пользователь).
class CriticalDivergenceCard extends ConsumerWidget {
  final CriticalDivergence divergence;
  final ValueChanged<String>? onOpenMedia;

  const CriticalDivergenceCard({
    super.key,
    required this.divergence,
    this.onOpenMedia,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final hasGem = divergence.hiddenGem != null;
    final hasDisappointment = divergence.disappointment != null;
    final isEmpty = !hasGem && !hasDisappointment;

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
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 16,
                color: Color(0xFFFBBF24), // text-amber-400
              ),
              const SizedBox(width: 8), // gap-2
              Text(
                t.tr('stats.taste.divergenceTitle'),
                style: const TextStyle(
                  fontSize: 16, // text-base
                  fontWeight: FontWeight.w600, // font-semibold
                  letterSpacing: -0.2, // tracking-tight
                  color: Colors.white,
                ),
              ),
            ],
          ),

          if (isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 128), // min-h-32
              alignment: Alignment.center,
              child: Text(
                t.tr('stats.taste.divergenceEmpty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: theme.textSecondary, // text-muted
                ),
              ),
            )
          else ...[
            const SizedBox(height: 16), // mb-4
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 540;

                final cards = <Widget>[
                  if (hasGem)
                    _DivergenceItemCard(
                      item: divergence.hiddenGem!,
                      isGem: true,
                      onTap: onOpenMedia != null
                          ? () => onOpenMedia!(divergence.hiddenGem!.id)
                          : null,
                      t: t,
                    ),
                  if (hasDisappointment)
                    _DivergenceItemCard(
                      item: divergence.disappointment!,
                      isGem: false,
                      onTap: onOpenMedia != null
                          ? () => onOpenMedia!(divergence.disappointment!.id)
                          : null,
                      t: t,
                    ),
                ];

                if (isWide) {
                  if (cards.length == 2) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 16), // gap-4
                        Expanded(child: cards[1]),
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 16),
                        const Spacer(),
                      ],
                    );
                  }
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        cards[i],
                      ],
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 12), // mt-3
            Text(
              '${t.tr('stats.taste.yourScore')} · ${t.tr('stats.taste.worldScore')}',
              style: const TextStyle(
                fontSize: 11, // text-[11px]
                color: Color(0xFF64748B), // text-slate-500
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DivergenceItemCard extends StatelessWidget {
  final DivergenceItem item;
  final bool isGem;
  final VoidCallback? onTap;
  final I18nDictionary t;

  const _DivergenceItemCard({
    required this.item,
    required this.isGem,
    required this.onTap,
    required this.t,
  });

  static String _formatScore(double score) {
    return score % 1 == 0 ? score.toInt().toString() : score.toStringAsFixed(1);
  }

  static String _formatDelta(double delta) {
    final prefix = delta >= 0 ? '+' : '';
    final val =
        delta % 1 == 0 ? delta.toInt().toString() : delta.toStringAsFixed(1);
    return '$prefix$val';
  }

  static String _typeLabel(I18nDictionary t, String type) {
    const known = {'all', 'anime', 'book', 'game', 'manga', 'movie', 'series'};
    if (known.contains(type)) {
      return t.tr('stats.genreCategories.$type');
    }
    return type;
  }

  @override
  Widget build(BuildContext context) {
    final headerText =
        isGem ? t.tr('stats.taste.hiddenGem') : t.tr('stats.taste.disappointment');
    final hintText = isGem
        ? t.tr('stats.taste.hiddenGemHint')
        : t.tr('stats.taste.disappointmentHint');
    final headerColor =
        isGem ? const Color(0xFF6EE7B7) : const Color(0xFFFDA4AF); // emerald-300 / rose-300
    final borderColor = isGem
        ? const Color(0x3310B981) // border-emerald-500/20
        : const Color(0x33F43F5E); // border-rose-500/20
    final bgColor = isGem
        ? const Color(0x0D10B981) // bg-emerald-500/5
        : const Color(0x0DF43F5E); // bg-rose-500/5

    final deltaBg = item.delta >= 0
        ? const Color(0x1A10B981) // bg-emerald-500/10
        : const Color(0x1AF43F5E); // bg-rose-500/10
    final deltaBorder = item.delta >= 0
        ? const Color(0x3310B981) // border-emerald-500/20
        : const Color(0x33F43F5E); // border-rose-500/20
    final deltaText = item.delta >= 0
        ? const Color(0xFF6EE7B7) // text-emerald-300
        : const Color(0xFFFDA4AF); // text-rose-300

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8), // rounded-lg
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16), // p-4
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Блок заголовка: иконка + ТАЙНЫЙ ШЕДЕВР / РАЗОЧАРОВАНИЕ
                Row(
                  children: [
                    Text(
                      isGem ? '💎' : '💔',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        headerText.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11, // text-[11px]
                          fontWeight: FontWeight.w600, // font-semibold
                          letterSpacing: 0.5, // tracking-wide
                          color: headerColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12), // gap-3

                // Медиа-информация: постер + тайтл + тип + оценки
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6), // rounded-md
                      child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                          ? Image.network(
                              item.coverUrl!,
                              width: 56, // w-14
                              height: 80, // h-20
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                width: 56,
                                height: 80,
                                color: Colors.white.withAlpha(13), // bg-white/5
                                alignment: Alignment.center,
                                child: const Icon(
                                  LucideIcons.image,
                                  size: 20,
                                  color: Color(0xFF64748B), // text-slate-500
                                ),
                              ),
                            )
                          : Container(
                              width: 56,
                              height: 80,
                              color: Colors.white.withAlpha(13),
                              alignment: Alignment.center,
                              child: const Icon(
                                LucideIcons.image,
                                size: 20,
                                color: Color(0xFF64748B),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12), // gap-3
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14, // text-sm
                              fontWeight: FontWeight.w600, // font-semibold
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2), // mt-0.5
                          Text(
                            '${_typeLabel(t, item.type)} · $hintText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12, // text-xs
                              color: Color(0xFF94A3B8), // text-slate-400
                            ),
                          ),
                          const SizedBox(height: 8), // mt-2
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12, // gap-x-3
                            runSpacing: 4, // gap-y-1
                            children: isGem
                                ? [
                                    Text(
                                      '★ ${_formatScore(item.userScore)}',
                                      style: const TextStyle(
                                        fontSize: 12, // text-xs
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFCD34D), // text-amber-300
                                      ),
                                    ),
                                    const Text(
                                      'vs',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B), // text-slate-500
                                      ),
                                    ),
                                    Text(
                                      '★ ${_formatScore(item.worldRating)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFCBD5E1), // text-slate-300
                                      ),
                                    ),
                                  ]
                                : [
                                    Text(
                                      '★ ${_formatScore(item.worldRating)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFCBD5E1), // text-slate-300
                                      ),
                                    ),
                                    const Text(
                                      'vs',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B), // text-slate-500
                                      ),
                                    ),
                                    Text(
                                      '★ ${_formatScore(item.userScore)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFFDA4AF), // text-rose-300
                                      ),
                                    ),
                                  ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12), // gap-3

                // Нижняя строка: бейдж разрыва
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.tr('stats.taste.divergenceBadge'),
                      style: const TextStyle(
                        fontSize: 12, // text-xs
                        color: Color(0xFF94A3B8), // text-slate-400
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ), // px-2.5 py-0.5
                      decoration: BoxDecoration(
                        color: deltaBg,
                        border: Border.all(color: deltaBorder),
                        borderRadius: BorderRadius.circular(9999), // rounded-full
                      ),
                      child: Text(
                        _formatDelta(item.delta),
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          fontWeight: FontWeight.bold, // font-bold
                          color: deltaText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
