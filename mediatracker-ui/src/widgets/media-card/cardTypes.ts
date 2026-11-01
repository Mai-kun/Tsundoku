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
  /** The card drives the optimistic series step itself; the callback receives
   *  the absolute post-step watched count (never a delta) so the parent can
   *  mirror the value without double-counting the click. */
  onEpisodeStep?: (item: MediaItem, newWatched: number) => void | Promise<void>;
}
