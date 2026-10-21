import { updateStatus } from "$shared/api/api";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$shared/types";
import { dropPromptState } from "$features/drop-reason/dropReasonPrompt.svelte";

export interface CardStatusState {
    changeStatus(newStatus: MediaStatus): Promise<void>;
}

export interface CardStatusOptions {
    getItem: () => MediaItem;
    getOnStatusChange: () =>
        | ((item: MediaItem, newStatus: MediaStatus) => void)
        | undefined;
    getOnProgressCommitted: () => () => void;
}

/**
 * Optimistic status switch: the badge flips immediately and rolls back only if
 * the server rejects it.
 */
export function createCardStatus(options: CardStatusOptions): CardStatusState {
    async function changeStatus(newStatus: MediaStatus) {
        const item = options.getItem();
        const prevStatus = item.status;
        item.status = newStatus;
        if (newStatus !== MEDIA_STATUS.dropped) {
            item.dropReason = null;
            item.dropNotes = null;
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
            options.getOnStatusChange()?.(item, prevStatus);
            console.error(error);
        }
    }

    return { changeStatus };
}