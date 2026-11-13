import { updateStatus } from "$shared/api/api";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$shared/types";
import { updateCachedDetailProgress } from "$features/prefetch-details/mediaDetailPrefetch";
import { readCardProgress, writeCardProgress } from "$entities/media/model/progressRules";
import { dropPromptState } from "$features/drop-reason/dropReasonPrompt.svelte";

export interface CardStatusState {
  changeStatus(newStatus: MediaStatus): Promise<void>;
}

export interface CardStatusOptions {
  getItem: () => MediaItem;
  getOnStatusChange: () => ((item: MediaItem, newStatus: MediaStatus) => void) | undefined;
  getOnProgressCommitted: () => () => void;
}

/**
 * Optimistic status switch: the badge flips immediately and rolls back only if
 * the server rejects it. The single automatic progress rule (rule 2) is applied
 * optimistically too: leaving "Completed" resets the progress, mirroring the
 * server's ChangeStatus so a refetch or an F5 shows exactly the same numbers.
 */
export function createCardStatus(options: CardStatusOptions): CardStatusState {
  async function changeStatus(newStatus: MediaStatus) {
    const item = options.getItem();
    const prevStatus = item.status;
    const leavesCompleted =
      prevStatus === MEDIA_STATUS.completed && newStatus !== MEDIA_STATUS.completed;
    const progressBeforeReset = leavesCompleted ? readCardProgress(item) : null;
    item.status = newStatus;
    if (newStatus !== MEDIA_STATUS.dropped) {
      item.dropReason = null;
      item.dropNotes = null;
    }
    if (leavesCompleted) {
      // Rule 2: leaving Completed is the only status change that resets progress.
      writeCardProgress(item, 0);
      updateCachedDetailProgress(item.id, 0);
    }
    options.getOnStatusChange()?.(item, newStatus);
    try {
      await updateStatus(item.id, newStatus);
      options.getOnProgressCommitted()();
      if (newStatus === MEDIA_STATUS.dropped) {
        dropPromptState.open({
          id: item.id,
          title: item.title,
          type: item.type,
          isAnime: (item as { isAnime?: boolean }).isAnime,
          dropReason: item.dropReason,
          dropNotes: item.dropNotes,
          onSaved: (reason, notes) => {
            item.dropReason = reason;
            item.dropNotes = notes;
            options.getOnStatusChange()?.(item, newStatus);
          },
        });
      }
    } catch (error) {
      item.status = prevStatus;
      if (progressBeforeReset !== null) {
        // The reset never happened server-side: restore the old progress.
        writeCardProgress(item, progressBeforeReset);
        updateCachedDetailProgress(item.id, progressBeforeReset);
      }
      options.getOnStatusChange()?.(item, prevStatus);
      console.error(error);
    }
  }

  return { changeStatus };
}
