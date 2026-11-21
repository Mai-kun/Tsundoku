/// 1:1 port of `mediatracker-ui/src/features/change-status/statusController.svelte.ts`.
///
/// Optimistic status switch: the badge flips immediately and rolls back only
/// if the server rejects it. The single automatic progress rule (rule 2) is
/// applied optimistically too: leaving "Completed" resets the progress,
/// mirroring the server's ChangeStatus so a refetch or an F5 shows exactly the
/// same numbers.
///
/// TS-мутация item-объекта → иммутабельные копии (решение #14): [onStatusChange]
/// получает обновлённый [MediaItem]; rollback восстанавливает предыдущий
/// (item сохранён вызывающей стороной).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../entities/media/model/progress_rules.dart';
import '../../shared/api/api.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';
import '../drop-reason/drop_reason_prompt.dart';
import '../prefetch-details/media_detail_prefetch.dart';

typedef OnStatusChanged = void Function(MediaItem item, MediaStatus newStatus);

class CardStatusOptions {
  final MediaItem Function() getItem;
  final OnStatusChanged? Function()? getOnStatusChange;
  final void Function() Function() getOnProgressCommitted;
  /// Инъекция ref для prefetch-кэша и drop-prompt провайдера (Riverpod).
  final Ref ref;

  const CardStatusOptions({
    required this.getItem,
    required this.getOnStatusChange,
    required this.getOnProgressCommitted,
    required this.ref,
  });
}

class CardStatusState {
  final Future<void> Function(MediaStatus newStatus) changeStatus;

  const CardStatusState({required this.changeStatus});
}

CardStatusState createCardStatus(CardStatusOptions options) {
  Future<void> changeStatus(MediaStatus newStatus) async {
    final ref = options.ref;
    final item = options.getItem();
    final prevItem = item;
    final prevStatus = item.status;
    final leavesCompleted =
        prevStatus == MediaStatus.completed && newStatus != MediaStatus.completed;
    final progressBeforeReset = leavesCompleted ? readCardProgress(item) : null;
    var current = item.copyWithFields(status: newStatus);
    if (newStatus != MediaStatus.dropped) {
      current = current.clearDropReasons();
    }
    if (leavesCompleted) {
      // Rule 2: leaving Completed is the only status change that resets
      // progress.
      current = writeCardProgress(current, 0);
      updateCachedDetailProgressRef(ref, item.id, 0);
    }
    options.getOnStatusChange?.call()?.call(current, newStatus);
    try {
      await ref.read(apiClientProvider).updateStatus(item.id, newStatus);
      options.getOnProgressCommitted()();
      if (newStatus == MediaStatus.dropped) {
        ref.read(dropPromptStateProvider.notifier).open(DropPromptTarget(
              id: current.id,
              title: current.title,
              type: current.type.wire,
              isAnime: current.isAnime,
              dropReason: current.dropReason,
              dropNotes: current.dropNotes,
              onSaved: (reason, notes) {
                final saved = current.copyWithFields(dropReason: reason, dropNotes: notes);
                options.getOnStatusChange?.call()?.call(saved, newStatus);
              },
            ));
      }
    } catch (error) {
      // Rollback: восстановить исходный item (статус/прогресс/причины).
      var restored = prevItem;
      if (progressBeforeReset != null) {
        // The reset never happened server-side: restore the old progress.
        restored = writeCardProgress(restored, progressBeforeReset);
        updateCachedDetailProgressRef(ref, item.id, progressBeforeReset);
      }
      options.getOnStatusChange?.call()?.call(restored, prevStatus);
      // console.error аналог — молча (как исходник), но без потерь для отладки.
    }
  }

  return CardStatusState(changeStatus: changeStatus);
}
