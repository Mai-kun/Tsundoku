export type CriterionKey =
    | "story"
    | "visuals"
    | "characters"
    | "sound"
    | "pacing"
    | "gameplay"
    | "writing"
    | "enjoyment";

export type DetailedScoreMap = Partial<Record<CriterionKey, number>>;

export interface CriterionAxis {
    key: CriterionKey;
    label: { ru: string; en: string };
}

export const CRITERION_KEYS: readonly CriterionKey[] = [
    "story",
    "visuals",
    "characters",
    "sound",
    "pacing",
    "gameplay",
    "writing",
    "enjoyment",
];

export function isCriterionKey(key: string): key is CriterionKey {
    return (CRITERION_KEYS as readonly string[]).includes(key);
}

const GAME_AXES: readonly CriterionAxis[] = [
    { key: "gameplay", label: { ru: "Геймплей", en: "Gameplay" } },
    { key: "story", label: { ru: "Сюжет и мир", en: "Story & Lore" } },
    { key: "visuals", label: { ru: "Графика и арт", en: "Visuals & Art" } },
    { key: "sound", label: { ru: "Музыка и звук", en: "Sound & OST" } },
    { key: "enjoyment", label: { ru: "Удовольствие", en: "Enjoyment" } },
];

const BOOK_AXES: readonly CriterionAxis[] = [
    { key: "story", label: { ru: "Сюжет", en: "Story" } },
    { key: "characters", label: { ru: "Персонажи", en: "Characters" } },
    { key: "writing", label: { ru: "Слог и стиль", en: "Writing Style" } },
    { key: "pacing", label: { ru: "Динамика", en: "Pacing" } },
    { key: "enjoyment", label: { ru: "Впечатление", en: "Impact" } },
];

const MANGA_AXES: readonly CriterionAxis[] = [
    { key: "story", label: { ru: "Сюжет", en: "Story" } },
    { key: "visuals", label: { ru: "Рисовка", en: "Art" } },
    { key: "characters", label: { ru: "Персонажи", en: "Characters" } },
    { key: "pacing", label: { ru: "Динамика", en: "Pacing" } },
    { key: "enjoyment", label: { ru: "Атмосфера", en: "Enjoyment" } },
];

const SCREEN_AXES: readonly CriterionAxis[] = [
    { key: "story", label: { ru: "Сюжет", en: "Story" } },
    { key: "visuals", label: { ru: "Визуал", en: "Visuals" } },
    { key: "characters", label: { ru: "Персонажи", en: "Characters" } },
    { key: "sound", label: { ru: "Звук и ОСТ", en: "Sound & OST" } },
    { key: "pacing", label: { ru: "Динамика", en: "Pacing" } },
];

export function getCriteriaAxes(media: { type: string; isAnime?: boolean }): readonly CriterionAxis[] {
    const rawType = (media?.type || "").toLowerCase();
    if (rawType === "game") {
        return GAME_AXES;
    }
    if (rawType === "book") {
        return BOOK_AXES;
    }
    if (rawType === "manga") {
        return MANGA_AXES;
    }
    return SCREEN_AXES;
}

export function parseDetailedScore(json?: string | null): DetailedScoreMap {
    if (!json || typeof json !== "string") return {};
    try {
        const parsed = JSON.parse(json);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            return {};
        }
        const result: DetailedScoreMap = {};
        for (const [key, val] of Object.entries(parsed)) {
            if (isCriterionKey(key) && typeof val === "number" && Number.isFinite(val)) {
                const rounded = Math.round(val);
                if (rounded >= 1 && rounded <= 10) {
                    result[key] = rounded;
                }
            }
        }
        return result;
    } catch {
        return {};
    }
}

export function serializeDetailedScore(map: DetailedScoreMap): string | null {
    if (!map || typeof map !== "object") return null;
    const clean: DetailedScoreMap = {};
    for (const [key, val] of Object.entries(map)) {
        if (isCriterionKey(key) && typeof val === "number" && Number.isFinite(val)) {
            const rounded = Math.round(val);
            if (rounded >= 1 && rounded <= 10) {
                clean[key] = rounded;
            }
        }
    }
    if (Object.keys(clean).length === 0) return null;
    return JSON.stringify(clean);
}

export function computeDetailedAverage(
    map: DetailedScoreMap,
): { exact: number; rounded: number; count: number } | null {
    if (!map || typeof map !== "object") return null;
    let sum = 0;
    let count = 0;
    for (const [key, val] of Object.entries(map)) {
        if (isCriterionKey(key) && typeof val === "number" && Number.isFinite(val)) {
            const rounded = Math.round(val);
            if (rounded >= 1 && rounded <= 10) {
                sum += rounded;
                count++;
            }
        }
    }
    if (count === 0) return null;
    const avg = sum / count;
    const exact = Math.round(avg * 10) / 10;
    const rounded = Math.min(10, Math.max(1, Math.round(avg)));
    return { exact, rounded, count };
}
