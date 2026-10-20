import { getReadingSettings, saveReadingSettings, type ReadingSettings } from "$shared/api/api";

const BOOK_PAGE_MINUTES_KEY = "tsundoku_reading_book_page_minutes";
const MANGA_CHAPTER_MINUTES_KEY = "tsundoku_reading_manga_chapter_minutes";
const CAST_SIZE_BY_CATEGORY_KEY = "tsundoku_cast_size_by_category";
const STAFF_SIZE_BY_CATEGORY_KEY = "tsundoku_staff_size_by_category";

export const DEFAULT_BOOK_PAGE_MINUTES = 1.5;
export const DEFAULT_MANGA_CHAPTER_MINUTES = 6.0;

export type PeopleCardSize = "compact" | "large";
type PeopleSizeMap = Record<string, PeopleCardSize>;

function readStoredNumber(key: string, defaultValue: number): number {
    if (typeof localStorage === "undefined") {
        return defaultValue;
    }
    const val = localStorage.getItem(key);
    if (!val) return defaultValue;
    const num = parseFloat(val);
    return isNaN(num) || num <= 0 ? defaultValue : num;
}

function readStoredMap(key: string): PeopleSizeMap {
    if (typeof localStorage === "undefined") return {};
    try {
        const parsed = JSON.parse(localStorage.getItem(key) ?? "{}");
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
            return parsed as PeopleSizeMap;
        }
    } catch {
        // Unreadable payload: fall through to an empty map.
    }
    return {};
}

function writeStoredMap(key: string, value: PeopleSizeMap): void {
    if (typeof localStorage === "undefined") return;
    localStorage.setItem(key, JSON.stringify(value));
}

class UiSettingsService {
    bookPageMinutes = $state<number>(readStoredNumber(BOOK_PAGE_MINUTES_KEY, DEFAULT_BOOK_PAGE_MINUTES));
    mangaChapterMinutes = $state<number>(readStoredNumber(MANGA_CHAPTER_MINUTES_KEY, DEFAULT_MANGA_CHAPTER_MINUTES));
    /** Thumbnail density of the characters / staff / voice-cast cards. Per media category and
        per block (cast vs staff), so switching an anime's cast never touches the manga staff view. */
    castSizeByCategory = $state<PeopleSizeMap>(readStoredMap(CAST_SIZE_BY_CATEGORY_KEY));
    staffSizeByCategory = $state<PeopleSizeMap>(readStoredMap(STAFF_SIZE_BY_CATEGORY_KEY));
    isLoaded = $state<boolean>(false);

    constructor() {
        this.load();
    }

    getCastSize(category: string): PeopleCardSize {
        return this.castSizeByCategory[category] ?? "compact";
    }

    setCastSize(category: string, size: PeopleCardSize): void {
        this.castSizeByCategory = { ...this.castSizeByCategory, [category]: size };
        writeStoredMap(CAST_SIZE_BY_CATEGORY_KEY, this.castSizeByCategory);
    }

    getStaffSize(category: string): PeopleCardSize {
        return this.staffSizeByCategory[category] ?? "compact";
    }

    setStaffSize(category: string, size: PeopleCardSize): void {
        this.staffSizeByCategory = { ...this.staffSizeByCategory, [category]: size };
        writeStoredMap(STAFF_SIZE_BY_CATEGORY_KEY, this.staffSizeByCategory);
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
