/// Порт `mediatracker-ui/src/widgets/stats/TrackerBadges.svelte`.
///
/// Виджет достижений медиатеки:
/// - Шапка: иконка Trophy + заголовок `stats.achievements` + счётчик разблокированных;
/// - 6 бейджей (Клуб сотен, Библиофил, Мастер стриков, Хранитель времени,
///   Перфекционист, Культурный омнивор);
/// - Для разблокированных: янтарная плашка `stats.unlocked` ('РАЗБЛОКИРОВАНО ✓');
/// - Для заблокированных: фиолетовый прогресс-бар и `stats.progress` с процентами.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class TrackerBadges extends ConsumerWidget {
  final AdvancedStats stats;

  const TrackerBadges({super.key, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final hours = [
      stats.gameHours,
      stats.movieHours,
      stats.seriesHours,
      stats.animeHours,
      stats.bookHours,
      stats.mangaHours,
    ];
    final activeMediaTypesCount = hours.where((h) => h > 0).length;

    final badges = [
      (
        id: 'hundred_club',
        translationKey: 'hundredClub',
        icon: LucideIcons.crown,
        target: 100,
        current: stats.completedTitles,
      ),
      (
        id: 'bibliophile',
        translationKey: 'bibliophile',
        icon: LucideIcons.bookOpen,
        target: 1000,
        current: stats.totalPagesRead + stats.totalChaptersRead,
      ),
      (
        id: 'streak_master',
        translationKey: 'streakMaster',
        icon: LucideIcons.flame,
        target: 7,
        current: stats.currentStreakDays,
      ),
      (
        id: 'time_keeper',
        translationKey: 'timeKeeper',
        icon: LucideIcons.clock,
        target: 100,
        current: stats.totalHours.floor(),
      ),
      (
        id: 'perfectionist',
        translationKey: 'perfectionist',
        icon: LucideIcons.star,
        target: 3,
        current: (stats.scoreDistribution[10] ?? 0.0).round(),
      ),
      (
        id: 'cultural_omnivore',
        translationKey: 'omnivore',
        icon: LucideIcons.compass,
        target: 4,
        current: activeMediaTypesCount,
      ),
    ];

    final unlockedCount = badges.where((b) => b.current >= b.target).length;
    final overallPercent =
        badges.isNotEmpty ? ((unlockedCount / badges.length) * 100).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Шапка: Трофей, заголовок, бейдж общего прогресса
        LayoutBuilder(
          builder: (context, constraints) {
            final isSm = constraints.maxWidth >= 640;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.trophy,
                      size: 20,
                      color: Color(0xFFFBBF24), // text-amber-400
                    ),
                    const SizedBox(width: 10), // gap-2.5
                    Text(
                      t.tr('stats.achievements'),
                      style: TextStyle(
                        fontSize: isSm ? 18 : 16, // text-base sm:text-lg
                        fontWeight: FontWeight.w600, // font-semibold
                        letterSpacing: -0.4, // tracking-tight
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ), // px-3 py-1
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                    border: Border.all(
                      color: const Color(0x33F59E0B), // border-amber-500/20
                    ),
                    color: const Color(0x1AF59E0B), // bg-amber-500/10
                  ),
                  child: Text(
                    t.tf('stats.unlockedCount', [unlockedCount, overallPercent]),
                    style: const TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600, // font-semibold
                      color: Color(0xFFFBBF24), // text-amber-400
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16), // mt-4

        // Сетка достижений: mt-4 grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cols = width >= 1024
                ? 3
                : width >= 768
                    ? 2
                    : 1;

            Widget buildBadgeCard(
              ({
                String id,
                String translationKey,
                IconData icon,
                int target,
                int current,
              }) badge,
            ) {
              final isUnlocked = badge.current >= badge.target;
              final progressPercent =
                  (badge.target > 0 ? (badge.current / badge.target) * 100 : 0.0)
                      .clamp(0.0, 100.0)
                      .round();

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151A26), // bg-[#151a26]
                  border: Border.all(
                    color: Colors.white.withAlpha(13), // border-white/5
                  ),
                  borderRadius: BorderRadius.circular(12), // rounded-xl
                ),
                padding: const EdgeInsets.all(16), // p-4
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40, // size-10
                          height: 40,
                          decoration: BoxDecoration(
                            color: isUnlocked
                                ? const Color(0x1AF59E0B) // bg-amber-500/10
                                : Colors.white.withAlpha(8), // bg-white/[0.03]
                            border: Border.all(
                              color: isUnlocked
                                  ? const Color(0x4DF59E0B) // border-amber-500/30
                                  : Colors.white.withAlpha(13), // border-white/5
                            ),
                            borderRadius: BorderRadius.circular(8), // rounded-lg
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            badge.icon,
                            size: 20,
                            color: isUnlocked
                                ? const Color(0xFFFBBF24) // text-amber-400
                                : const Color(0xFF71717A), // text-zinc-500
                          ),
                        ),
                        const SizedBox(width: 12), // gap-3
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.tr('stats.badges.${badge.translationKey}.title'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14, // text-sm
                                  fontWeight: FontWeight.w700, // font-bold
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2), // mt-0.5
                              Text(
                                t.tr('stats.badges.${badge.translationKey}.description'),
                                style: TextStyle(
                                  fontSize: 12, // text-xs
                                  height: 1.375, // leading-snug
                                  color: theme.textSecondary, // text-muted
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20), // mt-4 pt-1
                    if (isUnlocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ), // px-2.5 py-1
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6), // rounded-md
                          border: Border.all(
                            color: const Color(0x33F59E0B), // border-amber-500/20
                          ),
                          color: const Color(0x1AF59E0B), // bg-amber-500/10
                        ),
                        child: Text(
                          t.tr('stats.unlocked'),
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            fontWeight: FontWeight.w600, // font-semibold
                            color: Color(0xFFFBBF24), // text-amber-400
                          ),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9999),
                            child: Container(
                              height: 6, // h-1.5
                              width: double.infinity,
                              color: Colors.white.withAlpha(13), // bg-white/5
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: (progressPercent / 100).clamp(0.0, 1.0),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFA855F7), // bg-purple-500
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(9999)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6), // space-y-1.5
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t.tr('stats.progress'),
                                style: TextStyle(
                                  fontSize: 11, // text-[11px]
                                  color: theme.textSecondary, // text-muted
                                ),
                              ),
                              Text(
                                '${badge.current} / ${badge.target} ($progressPercent%)',
                                style: TextStyle(
                                  fontSize: 11, // text-[11px]
                                  color: theme.textSecondary, // text-muted
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < badges.length; i += cols) ...[
                  if (i > 0) const SizedBox(height: 16), // gap-4
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < cols; c++) ...[
                          if (c > 0) const SizedBox(width: 16), // gap-4
                          if (i + c < badges.length)
                            Expanded(child: buildBadgeCard(badges[i + c]))
                          else
                            const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
