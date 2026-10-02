import { updateStatus } from "$lib/api";
import { type MediaItem, type MediaStatus } from "$lib/types";

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
        options.getOnStatusChange()?.(item, newStatus);
        try {
            await updateStatus(item.id, newStatus);
            options.getOnProgressCommitted()();
        } catch (error) {
            item.status = prevStatus;
            options.getOnStatusChange()?.(item, prevStatus);
            console.error(error);
        }
    }

    return { changeStatus };
}