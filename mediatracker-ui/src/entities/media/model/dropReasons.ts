export interface DropReasonOption {
  key: string;
  label: { ru: string; en: string };
  icon?: string;
  mediaTypes?: string[]; // если ограничено конкретными типами медиа
}

export const DROP_REASONS: readonly DropReasonOption[] = [
  // Универсальные:
  {
    key: "boring",
    label: { ru: "Скучно / Затянуто", en: "Boring / Dragged out" },
  },
  {
    key: "lost_interest",
    label: { ru: "Пропал интерес / Остыл", en: "Lost interest / Grew cold" },
  },
  {
    key: "bad_plot",
    label: { ru: "Разочаровал сюжет / Слитый финал", en: "Disappointing plot / Ruined ending" },
  },
  {
    key: "annoying_characters",
    label: { ru: "Бесячие персонажи / Клише", en: "Annoying characters / Cliches" },
  },
  {
    key: "no_time",
    label: { ru: "Нехватка времени / Усталость", en: "No time / Burnout" },
  },
  // Специфичные для игр (game):
  {
    key: "too_hard",
    label: { ru: "Непроходимо / Слишком сложно", en: "Too hard / Unbeatable" },
    mediaTypes: ["game"],
  },
  {
    key: "grind",
    label: { ru: "Унылый гринд / Однообразие", en: "Tiresome grind / Repetitive" },
    mediaTypes: ["game"],
  },
  {
    key: "bad_perf",
    label: { ru: "Баги / Плохая оптимизация", en: "Bugs / Poor optimization" },
    mediaTypes: ["game"],
  },
  // Специфичные для книг и манги (book, manga):
  {
    key: "bad_translation",
    label: { ru: "Ужасный / Машинный перевод", en: "Terrible / Machine translation" },
    mediaTypes: ["book", "manga"],
  },
  {
    key: "art_downgrade",
    label: { ru: "Испортилась рисовка", en: "Art downgrade" },
    mediaTypes: ["manga"],
  },
  {
    key: "abandoned",
    label: { ru: "Заброшено автором / Заморожено", en: "Abandoned / On hiatus" },
    mediaTypes: ["book", "manga"],
  },
  // Специфичные для аниме и сериалов (anime, tvshow):
  {
    key: "fillers",
    label: { ru: "Филлеры / Вода", en: "Fillers / Padding" },
    mediaTypes: ["tvshow", "anime"],
  },
  // Другое:
  {
    key: "other",
    label: { ru: "Другая причина", en: "Other reason" },
  },
];

const REASON_MAP = new Map<string, DropReasonOption>(
  DROP_REASONS.map((reason) => [reason.key, reason]),
);

export function getDropReasonsForMediaType(
  mediaType?: string,
  isAnime?: boolean,
): DropReasonOption[] {
  if (!mediaType) return [...DROP_REASONS];
  const normalizedType = mediaType.toLowerCase();

  return DROP_REASONS.filter((option) => {
    if (!option.mediaTypes || option.mediaTypes.length === 0) {
      return true;
    }
    if (option.mediaTypes.includes(normalizedType)) {
      return true;
    }
    if (isAnime && option.mediaTypes.includes("anime")) {
      return true;
    }
    return false;
  });
}

export function getDropReasonLabel(key: string, lang: "ru" | "en" = "ru"): string {
  if (!key || key === "unspecified") {
    return lang === "ru" ? "Не указана" : "Not specified";
  }
  const option = REASON_MAP.get(key);
  if (option) {
    return option.label[lang] || option.label.ru;
  }
  return key;
}
