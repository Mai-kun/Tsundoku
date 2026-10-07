const PREFIX = "tsundoku_";

const DETAIL_VIEWS = new Set(["detail", "seasons"]);

class UiSettingsService {
    lastView = $state<string>(this.read("last_view", "home"));
    groupByType = $state<boolean>(this.read("group_by_type", false));
    sortOption = $state<string>(this.read("sort_option", "newest"));
    statusFilter = $state<string | number>(this.read("status_filter", "all"));

    private read<T>(key: string, fallback: T): T {
        if (typeof window === "undefined") return fallback;
        try {
            const raw = localStorage.getItem(PREFIX + key);
            return raw !== null ? (JSON.parse(raw) as T) : fallback;
        } catch {
            return fallback;
        }
    }

    private write<T>(key: string, value: T): void {
        try {
            localStorage.setItem(PREFIX + key, JSON.stringify(value));
        } catch {}
    }

    setLastView(view: string): void {
        if (DETAIL_VIEWS.has(view)) return;
        this.lastView = view;
        this.write("last_view", view);
    }

    setGroupByType(enabled: boolean): void {
        this.groupByType = enabled;
        this.write("group_by_type", enabled);
    }

    setSortOption(sort: string): void {
        this.sortOption = sort;
        this.write("sort_option", sort);
    }

    setStatusFilter(filter: string | number): void {
        this.statusFilter = filter;
        this.write("status_filter", filter);
    }
}

export const uiSettings = new UiSettingsService();
