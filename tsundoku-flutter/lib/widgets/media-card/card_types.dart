/// 1:1 port of `mediatracker-ui/src/widgets/media-card/cardTypes.ts`.
///
/// Единый контракт колбеков карточек: TS-интерфейс `MediaCardProps` (Svelte
/// деконструирует его в пропы) → Dart-класс, который specialized-карточки и
/// [BaseCard] получают целиком (решение #33: вместо 10 named-параметров × 8
/// виджетов — один объект, состав полей 1-в-1).
library;

import 'dart:async';

import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';

class CardTimeHint {
  final String label;
  final bool canFinishNow;

  const CardTimeHint({required this.label, required this.canFinishNow});
}

/// Every specialised card accepts the same callbacks, so MediaCard can spread
/// them.
class MediaCardProps {
  final MediaItem item;
  final CardTimeHint? timeHint;
  final bool showProgress;
  final void Function(MediaItem item)? onOpen;
  final Future<void> Function(String id, int currentProgress)? onProgress;
  final void Function()? onProgressCommitted;
  final void Function(MediaItem item, MediaStatus newStatus)? onStatusChange;
  final Future<void> Function(MediaItem item)? onDelete;
  final void Function(MediaItem item)? onEdit;

  /// The card drives the optimistic series step itself; the callback receives
  /// the absolute post-step watched count (never a delta) so the parent can
  /// mirror the value without double-counting the click.
  ///
  /// TS: `void | Promise<void>` → FutureOr (синхронные колбеки допустимы).
  final FutureOr<void> Function(MediaItem item, int newWatched)? onEpisodeStep;

  const MediaCardProps({
    required this.item,
    this.timeHint,
    this.showProgress = true,
    this.onOpen,
    this.onProgress,
    this.onProgressCommitted,
    this.onStatusChange,
    this.onDelete,
    this.onEdit,
    this.onEpisodeStep,
  });

  /// `{...props, item: другой}` — 1-в-1 с TS-spread в specialized-карточках.
  MediaCardProps withItem(MediaItem newItem) => MediaCardProps(
        item: newItem,
        timeHint: timeHint,
        showProgress: showProgress,
        onOpen: onOpen,
        onProgress: onProgress,
        onProgressCommitted: onProgressCommitted,
        onStatusChange: onStatusChange,
        onDelete: onDelete,
        onEdit: onEdit,
        onEpisodeStep: onEpisodeStep,
      );
}
