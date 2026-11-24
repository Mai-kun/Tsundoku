import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_image.dart';

/// 1:1 порт `mediatracker-ui/src/widgets/goals/GoalCard.svelte`.
///
/// Карточка цели:
/// - Иконка цели (эмодзи в elevated-контейнере)
/// - Заголовок и опциональное описание
/// - Счётчик прогресса `currentCount / targetCount` и процент
/// - Градиентный/изумрудный прогресс-бар + бейдж «Выполнено»
/// - Превью завершенных тайтлов (обложки 48x48 с переходом к деталям)
/// - Кнопка удаления цели (появляется при наведении)
class GoalCard extends ConsumerStatefulWidget {
  final GoalDto goal;
  final ValueChanged<String> onOpenMedia;
  final ValueChanged<GoalDto> onDelete;

  const GoalCard({
    super.key,
    required this.goal,
    required this.onOpenMedia,
    required this.onDelete,
  });

  @override
  ConsumerState<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<GoalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final theme =
        Theme.of(context).extension<TsundokuTheme>() ?? TsundokuTheme.obsidian;

    final percent = widget.goal.targetCount > 0
        ? math.min(
            100,
            ((widget.goal.currentCount / widget.goal.targetCount) * 100).round(),
          )
        : 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: theme.bgCard,
          border: Border.all(
            color: _hovered
                ? Colors.white.withAlpha(51) // hover:border-white/20
                : Colors.white.withAlpha(20), // border-white/[0.08]
          ),
          borderRadius: BorderRadius.circular(12), // rounded-xl
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16), // p-4
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Верхняя строка: иконка + заголовок + описание
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44, // size-11
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.bgElevated,
                          border: Border.all(
                            color: Colors.white.withAlpha(20), // border-white/[0.08]
                          ),
                          borderRadius: BorderRadius.circular(8), // rounded-lg
                        ),
                        alignment: Alignment.center,
                        child: _buildGoalIcon(widget.goal.icon, theme),
                      ),
                      const SizedBox(width: 12), // gap-3
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 32), // pr-8
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.goal.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14, // text-sm
                                  fontWeight: FontWeight.w600, // font-semibold
                                  color: theme.textPrimary, // text-ink
                                ),
                              ),
                              if (widget.goal.description != null &&
                                  widget.goal.description!.isNotEmpty) ...[
                                const SizedBox(height: 2), // mt-0.5
                                Text(
                                  widget.goal.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12, // text-xs
                                    height: 1.5, // leading-relaxed
                                    color: theme.textSecondary, // text-muted
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12), // gap-3

                  // Прогресс
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${widget.goal.currentCount} / ${widget.goal.targetCount}',
                            style: TextStyle(
                              fontSize: 14, // text-sm
                              fontWeight: FontWeight.bold, // font-bold
                              color: theme.textPrimary, // text-ink
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            '$percent%',
                            style: TextStyle(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w500, // font-medium
                              color: theme.textSecondary, // text-muted
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6), // mb-1.5
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9999), // rounded-full
                        child: Container(
                          height: 10, // h-2.5
                          width: double.infinity,
                          color: Colors.white.withAlpha(13), // bg-track
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (percent / 100.0).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9999),
                                color: widget.goal.isCompleted
                                    ? const Color(0xCC10B981) // bg-emerald-500/80
                                    : null,
                                gradient: widget.goal.isCompleted
                                    ? null
                                    : LinearGradient(
                                        colors: [
                                          theme.accentBright,
                                          const Color(0xFF818CF8),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.goal.isCompleted) ...[
                        const SizedBox(height: 8), // mt-2
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ), // px-2 py-0.5
                          decoration: BoxDecoration(
                            color: const Color(0x2610B981), // bg-emerald-500/15
                            border: Border.all(
                              color: const Color(0x6634D399), // border-emerald-400/40
                            ),
                            borderRadius: BorderRadius.circular(6), // rounded-md
                          ),
                          child: Text(
                            t.tr('goals.completedBadge'),
                            style: const TextStyle(
                              fontSize: 11, // text-[11px]
                              fontWeight: FontWeight.w600, // font-semibold
                              color: Color(0xFF6EE7B7), // text-emerald-300
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12), // gap-3

                  // Обложки выполненных тайтлов
                  if (widget.goal.completedItems.isNotEmpty)
                    Tooltip(
                      message: t.tr('goals.overallProgress'),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0;
                                i < widget.goal.completedItems.length;
                                i++) ...[
                              if (i > 0) const SizedBox(width: 6), // gap-1.5
                              _MediaThumb(
                                item: widget.goal.completedItems[i],
                                onTap: () => widget.onOpenMedia(
                                  widget.goal.completedItems[i].id,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      t.tr('goals.noMatches'),
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        color: theme.textSecondary, // text-muted
                      ),
                    ),
                ],
              ),
            ),

            // Кнопка удаления (hover)
            Positioned(
              top: 12, // top-3
              right: 12, // right-3
              child: Opacity(
                opacity: _hovered ? 1.0 : 0.0,
                child: Tooltip(
                  message: t.tr('goals.deleteGoal'),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('goal-delete-btn'),
                      borderRadius: BorderRadius.circular(6), // rounded-md
                      onTap: () => widget.onDelete(widget.goal),
                      child: Container(
                        width: 32, // w-8
                        height: 32, // h-8
                        decoration: BoxDecoration(
                          color: theme.bgElevated,
                          border: Border.all(
                            color: Colors.white.withAlpha(26), // border-white/10
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          LucideIcons.trash2,
                          size: 14,
                          color: theme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalIcon(String iconStr, TsundokuTheme theme) {
    final mapped = _mapLucideIcon(iconStr);
    if (mapped != null) {
      return Icon(
        mapped,
        size: 22,
        color: const Color(0xFF818CF8), // text-accent-soft / indigo-400
      );
    }
    return Text(
      iconStr,
      style: const TextStyle(fontSize: 20), // text-xl
    );
  }

  static IconData? _mapLucideIcon(String key) {
    final normalized = key.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
    return switch (normalized) {
      'book' || 'books' || 'bookopen' => LucideIcons.bookOpen,
      'game' || 'games' || 'gamepad' || 'gamepad2' => LucideIcons.gamepad2,
      'tv' || 'tvshow' || 'television' => LucideIcons.tv,
      'film' || 'movie' || 'movies' || 'clapperboard' => LucideIcons.film,
      'trophy' => LucideIcons.trophy,
      'star' => LucideIcons.star,
      'target' => LucideIcons.target,
      'heart' => LucideIcons.heart,
      'flame' || 'fire' => LucideIcons.flame,
      'compass' => LucideIcons.compass,
      'crown' => LucideIcons.crown,
      'clock' => LucideIcons.clock,
      'music' || 'headphones' => LucideIcons.music,
      'bookmark' => LucideIcons.bookmark,
      'library' => LucideIcons.library,
      'check' || 'checkcircle' => LucideIcons.checkCircle,
      'sparkles' => LucideIcons.sparkles,
      _ => null,
    };
  }
}

class _MediaThumb extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _MediaThumb({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = item.title as String;
    final coverUrl = item.coverUrl as String?;
    final id = item.id as String;

    return Tooltip(
      message: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('goal-item-$id'),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 48, // size-12
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withAlpha(26), // border-white/10
              ),
              borderRadius: BorderRadius.circular(6), // rounded-md
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? TsundokuImage(
                      src: coverUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.white.withAlpha(13),
                        alignment: Alignment.center,
                        child: const Text(
                          '?',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.white.withAlpha(13),
                      alignment: Alignment.center,
                      child: const Text(
                        '?',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
