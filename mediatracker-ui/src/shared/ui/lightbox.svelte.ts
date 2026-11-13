import { writable } from "svelte/store";

/**
 * App-wide lightbox state. A single <ImageLightbox /> lives at the top of AppShell, outside every
 * transformed container: `.view-fade` applies a transform, and inside one `position: fixed`
 * centers against that column instead of the monitor. Per-section instances therefore rendered the
 * lightbox off-center; everything now routes through this store instead.
 */
const lightboxUrl = writable<string | null>(null);
/** Optional one-line caption (a person's name, a screenshot title) shown under the image. */
const lightboxCaption = writable<string | null>(null);

/** Open the global lightbox with the given (full-size) image URL and optional caption. */
export function openLightbox(url: string | null | undefined, caption?: string | null) {
  if (!url) return;
  lightboxUrl.set(url);
  lightboxCaption.set(caption ?? null);
}

/** Close the global lightbox. */
export function closeLightbox() {
  lightboxUrl.set(null);
  lightboxCaption.set(null);
}

export { lightboxUrl, lightboxCaption };
