import type { MediaItem, MediaStatus } from "$shared/types";

/** Every specialised card accepts the same callbacks, so MediaCard can spread them. */
export interface MediaCardProps {
    item: MediaItem;
    onOpen?: (item: MediaItem) => void;
    onProgress?: (id: string, currentProgress: number) => Promise<void>;
    onProgressCommitted?: () => void;
    onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
    onDelete?: (item: MediaItem) => Promise<void>;
    onEdit?: (item: MediaItem) => void;
    onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
}