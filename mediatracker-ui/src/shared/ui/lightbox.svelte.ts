import { writable } from "svelte/store";

/**
 * App-wide lightbox state. A single <ImageLightbox /> lives at the top of AppShell, outside every
 * transformed container: `.view-fade` applies a transform, and inside one `position: fixed`
 * centers against that column instead of the monitor. Per-section instances therefore rendered the
 * lightbox off-center; everything now routes through this store instead.
 */
const lightboxUrl = writable<string | null>(null);

/** Open the global lightbox with the given (full-size) image URL. */
export function openLightbox(url: string | null | undefined) {
  if (!url) return;
  lightboxUrl.set(url);
}

/** Close the global lightbox. */
export function closeLightbox() {
  lightboxUrl.set(null);
}

export { lightboxUrl };
