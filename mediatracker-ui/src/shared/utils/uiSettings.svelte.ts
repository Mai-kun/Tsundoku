import { getReadingSettings, saveReadingSettings, type ReadingSettings } from "$shared/api/api";

const BOOK_PAGE_MINUTES_KEY = "tsundoku_reading_book_page_minutes";
const MANGA_CHAPTER_MINUTES_KEY = "tsundoku_reading_manga_chapter_minutes";
const PEOPLE_CARD_SIZE_KEY = "tsundoku_people_card_size";

export const DEFAULT_BOOK_PAGE_MINUTES = 1.5;
export const DEFAULT_MANGA_CHAPTER_MINUTES = 6.0;

export type PeopleCardSize = "compact" | "large";

function readStoredNumber(key: string, defaultValue: number): number {
    if (typeof localStorage === "undefined") {
        return defaultValue;
    }
    const val = localStorage.getItem(key);
    if (!val) return defaultValue;
    const num = parseFloat(val);
    return isNaN(num) || num <= 0 ? defaultValue : num;
}

function readStoredPeopleCardSize(): PeopleCardSize {
    if (typeof localStorage === "undefined") return "compact";
    return localStorage.getItem(PEOPLE_CARD_SIZE_KEY) === "large" ? "large" : "compact";
}

class UiSettingsService {
    bookPageMinutes = $state<number>(readStoredNumber(BOOK_PAGE_MINUTES_KEY, DEFAULT_BOOK_PAGE_MINUTES));
    mangaChapterMinutes = $state<number>(readStoredNumber(MANGA_CHAPTER_MINUTES_KEY, DEFAULT_MANGA_CHAPTER_MINUTES));
    /** Thumbnail density of the characters / staff / voice-cast cards. Separate key, no backend — purely presentation. */
    peopleCardSize = $state<PeopleCardSize>(readStoredPeopleCardSize());
    isLoaded = $state<boolean>(false);

    constructor() {
        this.load();
    }

    setPeopleCardSize(size: PeopleCardSize): void {
        this.peopleCardSize = size;
        if (typeof localStorage !== "undefined") {
            localStorage.setItem(PEOPLE_CARD_SIZE_KEY, size);
        }
    }

    async load(): Promise<void> {
        try {
            const data = await getReadingSettings();
            if (data) {
                if (typeof data.bookPageMinutes === "number" && data.bookPageMinutes > 0) {
                    this.bookPageMinutes = data.bookPageMinutes;
                    if (typeof localStorage !== "undefined") {
                        localStorage.setItem(BOOK_PAGE_MINUTES_KEY, String(data.bookPageMinutes));
                    }
                }
                if (typeof data.mangaChapterMinutes === "number" && data.mangaChapterMinutes > 0) {
                    this.mangaChapterMinutes = data.mangaChapterMinutes;
                    if (typeof localStorage !== "undefined") {
                        localStorage.setItem(MANGA_CHAPTER_MINUTES_KEY, String(data.mangaChapterMinutes));
                    }
                }
            }
        } catch {
            // Keep localStorage / default values if backend is unreachable
        } finally {
            this.isLoaded = true;
        }
    }

    async setReadingSpeed(bookPageMinutes: number, mangaChapterMinutes: number): Promise<ReadingSettings> {
        this.bookPageMinutes = bookPageMinutes;
        this.mangaChapterMinutes = mangaChapterMinutes;
        if (typeof localStorage !== "undefined") {
            localStorage.setItem(BOOK_PAGE_MINUTES_KEY, String(bookPageMinutes));
            localStorage.setItem(MANGA_CHAPTER_MINUTES_KEY, String(mangaChapterMinutes));
        }
        return await saveReadingSettings({ bookPageMinutes, mangaChapterMinutes });
    }
}

export const uiSettings = new UiSettingsService();
