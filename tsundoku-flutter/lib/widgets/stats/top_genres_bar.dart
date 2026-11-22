/// Порт `mediatracker-ui/src/widgets/stats/TopGenresBar.svelte`.
///
/// Виджет топ-жанров:
/// - Заголовок `stats.topGenres` с иконкой Sparkles;
/// - Селектор категорий (Все, Игры, Фильмы, Сериалы, Аниме, Манга, Книги);
/// - Сегментированный бар с 8 цветами PALETTE и Tooltip;
/// - Сетка до 8 жанров (цветная точка, название, счётчик, бейдж с процентом);
/// - Empty state при отсутствии данных по категории.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/genre_label.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

typedef GenreItem = GenreCount;

class TopGenresBar extends ConsumerStatefulWidget {
  final List<GenreItem> genres;
  final Map<String, List<GenreItem>> genresByType;

  const TopGenresBar({
    super.key,
    this.genres = const [],
    this.genresByType = const {},
  });

  @override
  ConsumerState<TopGenresBar> createState() => _TopGenresBarState();
}

class _TopGenresBarState extends ConsumerState<TopGenresBar> {
  String _selectedType = 'all';

  static const List<String> _categories = [
    'all',
    'game',
    'movie',
    'series',
    'anime',
    'manga',
    'book',
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final palette = [
      theme.chartAmber,
      theme.chartCyan,
      theme.chartIndigo,
      theme.chartRose,
      theme.chartBlue,
      theme.chartPink,
      theme.chartEmerald,
      theme.chartViolet,
    ];

    final currentGenres = _selectedType == 'all'
        ? widget.genres
        : (widget.genresByType[_selectedType] ?? const []);
    final displayGenres =
        currentGenres.length > 8 ? currentGenres.sublist(0, 8) : currentGenres;

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
          // Шапка: заголовок + селектор категорий
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 640;

              final titleWidget = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.sparkles,
                    size: 16,
                    color: Color(0xFFFBBF24), // text-amber-400
                  ),
                  const SizedBox(width: 8), // gap-2
                  Text(
                    t.tr('stats.topGenres'),
                    style: const TextStyle(
                      fontSize: 16, // text-base
                      fontWeight: FontWeight.w600, // font-semibold
                      letterSpacing: -0.2, // tracking-tight
                      color: Colors.white,
                    ),
                  ),
                ],
              );

              final selectorWidget = Container(
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8), // bg-white/[0.03]
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                ),
                padding: const EdgeInsets.all(4), // p-1
                child: Row(
                  children: [
                    for (final cat in _categories)
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedType = cat),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            height: 32, // h-8
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _selectedType == cat
                                  ? theme.accent.withAlpha(77) // bg-accent-bright/30
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6), // rounded-md
                            ),
                            child: Text(
                              t.tr('stats.genreCategories.$cat'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w500, // font-medium
                                color: _selectedType == cat
                                    ? Colors.white
                                    : const Color(0xFF94A3B8), // text-slate-400
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );

              if (isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        titleWidget,
                        const SizedBox(width: 12),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: selectorWidget,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const SizedBox(height: 12),
                    selectorWidget,
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16), // mb-4

          // Прогресс-бар жанров: h-3 w-full rounded-full bg-white/5
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: Container(
              height: 12, // h-3
              width: double.infinity,
              color: Colors.white.withAlpha(13), // bg-white/5
              child: displayGenres.isEmpty
                  ? ColoredBox(color: Colors.white.withAlpha(13))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        var usedW = 0.0;

                        return Row(
                          children: [
                            for (var i = 0; i < displayGenres.length; i++)
                              Builder(
                                builder: (context) {
                                  final item = displayGenres[i];
                                  final pct = item.percentage.clamp(0.0, 100.0);
                                  final rawW = w * (pct / 100);
                                  final segW =
                                      rawW.clamp(0.0, (w - usedW).clamp(0.0, w));
                                  usedW += segW;

                                  final color = palette[i % palette.length];
                                  final label =
                                      genreLabel(item.genre, t, locale);

                                  return SizedBox(
                                    width: segW,
                                    height: 12,
                                    child: Tooltip(
                                      message: '$label: ${item.percentage.round()}%',
                                      child: ColoredBox(color: color),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16), // mt-4

          // Сетка жанров
          if (displayGenres.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 104),
              alignment: Alignment.center,
              child: Text(
                locale == Locale.ru
                    ? 'Нет данных о жанрах в этой категории'
                    : 'No genre data for this category',
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: theme.textSecondary, // text-muted
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final cols = width >= 768
                    ? 4
                    : width >= 640
                        ? 3
                        : 2;

                Widget buildGenreCard(GenreItem item, int index) {
                  final color = palette[index % palette.length];
                  final label = genreLabel(item.genre, t, locale);

                  return Row(
                    children: [
                      Container(
                        width: 10, // size-2.5
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w500, // font-medium
                            color: Color(0xFFE2E8F0), // text-slate-200
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item.count}',
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: theme.textSecondary, // text-slate-400
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ), // px-1 py-0.5
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(13), // bg-white/5
                          borderRadius: BorderRadius.circular(4), // rounded
                        ),
                        child: Text(
                          '${item.percentage.round()}%',
                          style: TextStyle(
                            fontSize: 10, // text-[10px]
                            color: theme.textSecondary, // text-slate-400
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < displayGenres.length; i += cols) ...[
                      if (i > 0) const SizedBox(height: 12), // gap-3
                      Row(
                        children: [
                          for (var c = 0; c < cols; c++) ...[
                            if (c > 0) const SizedBox(width: 12),
                            if (i + c < displayGenres.length)
                              Expanded(
                                child: buildGenreCard(
                                  displayGenres[i + c],
                                  i + c,
                                ),
                              )
                            else
                              const Expanded(child: SizedBox.shrink()),
                          ],
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
