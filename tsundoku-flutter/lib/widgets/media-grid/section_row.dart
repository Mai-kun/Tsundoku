/// 1:1 port of `mediatracker-ui/src/widgets/media-grid/SectionRow.svelte`.
///
/// Секция сетки (сегменты секций — см. virtualGrid ⏭️): заголовок 25px
/// font-bold tracking-wide + бейдж-счётчик (bg-surface text-muted, rounded-full)
/// + MediaGrid-слайверы. Возвращает список слайверов — встраивается в общий
/// CustomScrollView страницы (Phase 3).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';
import 'media_grid.dart';

/// Секция сетки: [title] + счётчик + [MediaGrid] (loading=false, error=null).
class SectionRow extends ConsumerWidget {
  final String title;
  final List<MediaItem> items;
  final VoidCallback? onRetry;
  final void Function(MediaItem item)? onOpen;
  final Future<void> Function(String id, int currentProgress)? onProgress;
  final VoidCallback? onProgressCommitted;
  final void Function(MediaItem item, MediaStatus newStatus)? onStatusChange;
  final Future<void> Function(MediaItem item)? onDelete;
  final void Function(MediaItem item)? onEdit;
  final FutureOr<void> Function(MediaItem item, int newWatched)? onEpisodeStep;

  const SectionRow({
    super.key,
    required this.title,
    required this.items,
    this.onRetry,
    this.onOpen,
    this.onProgress,
    this.onProgressCommitted,
    this.onStatusChange,
    this.onDelete,
    this.onEdit,
    this.onEpisodeStep,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final th = TsundokuTheme.of(context);

    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          // space-y-3 между заголовком и сеткой: нижний отступ 12px (сетка
          // сама даёт верхний rowGap).
          padding: const EdgeInsets.only(bottom: 0),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 25, // text-[25px]
                  fontWeight: FontWeight.w700, // font-bold
                  letterSpacing: 0.5, // tracking-wide @ 25px (0.025em)
                  color: Colors.white, // text-white
                ),
              ),
              const SizedBox(width: 8), // gap-2
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 2), // px-2.5 py-0.5
                decoration: BoxDecoration(
                  color: th.bgSurface, // bg-surface
                  borderRadius: BorderRadius.circular(999), // rounded-full
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    color: th.textMuted, // text-muted
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)), // space-y-3
      MediaGrid(
        items: items,
        loading: false,
        error: null,
        onRetry: onRetry,
        onOpen: onOpen,
        onProgress: onProgress,
        onProgressCommitted: onProgressCommitted,
        onStatusChange: onStatusChange,
        onDelete: onDelete,
        onEdit: onEdit,
        onEpisodeStep: onEpisodeStep,
      ),
    ]);
  }
}
