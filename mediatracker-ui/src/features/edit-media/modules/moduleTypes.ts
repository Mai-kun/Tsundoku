import type { SeasonDraft } from "$features/create-media/TvShowFormFields.svelte";
import type { MediaQuote, MediaType } from "$shared/types";

/**
 * The type-specific field bundle the editor keeps in one bindable object, so `CategoryFieldsModule`
 * can be dropped into any screen with a single prop instead of a dozen loose strings. Every value
 * stays a form-shaped string/boolean; payload building remains the caller's job.
 */
export interface CategoryDraft {
  platform: string;
  hoursPlayed: string;
  author: string;
  bookFormat: string;
  totalPages: string;
  totalChapters: string;
  bookTotalVolumes: string;
  currentVolume: string;
  durationMinutes: string;
  isAnime: boolean;
  studio: string;
  network: string;
  seasons: SeasonDraft[];
}

/** Fresh, empty category bundle; every call returns a new object so callers can own it in `$state`. */
export function emptyCategoryDraft(): CategoryDraft {
  return {
    platform: "",
    hoursPlayed: "",
    author: "",
    bookFormat: "book",
    totalPages: "",
    totalChapters: "",
    bookTotalVolumes: "",
    currentVolume: "",
    durationMinutes: "",
    isAnime: false,
    studio: "",
    network: "",
    seasons: [],
  };
}

/**
 * Quotes are edited as plain objects and serialised to `quotesJson` by the caller, which keeps the
 * module free of any API dependency (the same list can be rendered on a media page read-only).
 */
export type QuoteDraft = MediaQuote;

/** Identifiers of the six editor blocks, used for connector wiring and hover tracking. */
export type EditModuleId = "base" | "altTitles" | "category" | "notes" | "quotes" | "images";

export const EDIT_MEDIA_TYPES: MediaType[] = ["game", "movie", "tvshow", "book", "manga"];
