import type { MediaItem, MediaStatus } from "$shared/types";

export interface CardTimeHint {
    label: string;
    canFinishNow: boolean;
}

/** Every specialised card accepts the same callbacks, so MediaCard can spread them. */
export interface MediaCardProps {
    item: MediaItem;
    timeHint?: CardTimeHint | null;
    showProgress?: boolean;
    onOpen?: (item: MediaItem) => void;
    onProgress?: (id: string, currentProgress: number) => Promise<void>;
    onProgressCommitted?: () => void;
    onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
    onDelete?: (item: MediaItem) => Promise<void>;
    onEdit?: (item: MediaItem) => void;
    onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
}
