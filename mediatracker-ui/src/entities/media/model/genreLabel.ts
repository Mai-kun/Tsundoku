import { i18n } from "$shared/i18n/index.svelte";

/**
 * Canonical genre keys (camelCase translations keys from stats.genres) whose natural
 * camelCasing from the Title Case genre name does not produce the key.
 */
const ALIASES: Record<string, string> = {
  "sci fi": "sciFi",
  "slice of life": "sliceOfLife",
  "game show": "gameShow",
  "talk show": "talkShow",
  "martial arts": "martialarts",
  "board & card": "boardAndCard",
  "board and card": "boardAndCard",
  "utilities & software": "utilitiesAndSoftware",
  "utilities and software": "utilitiesAndSoftware",
  "programming & it": "programmingAndIt",
  "programming and it": "programmingAndIt",
  "business & economics": "businessAndEconomics",
  "business and economics": "businessAndEconomics",
  "art & design": "artAndDesign",
  "art and design": "artAndDesign",
  // Legacy canonical names still stored in old rows of tracker.db
  reality: "realityTv",
  kids: "family",
};

/**
 * Dictionary-driven Russian fallbacks (generated from MediaTracker.Server/Resources/genres-dictionary.json).
 * Used when the i18n catalog has no entry for the canonical name — offline imports can carry
 * genres the stats translations never heard of (e.g. "Donghua").
 */
const RU_FALLBACKS: Record<string, string> = {
  ["action"]: "Боевик",
  ["adventure"]: "Приключения",
  ["animals"]: "Животные",
  ["animation"]: "Анимация",
  ["arcade"]: "Аркада",
  ["art & design"]: "Искусство и дизайн",
  ["biography"]: "Биография",
  ["board & card"]: "Настольные игры",
  ["boys' love"]: "Сёнэн-ай",
  ["business & economics"]: "Бизнес и экономика",
  ["casual"]: "Казуальная игра",
  ["comedy"]: "Комедия",
  ["crime"]: "Криминал",
  ["cyberpunk"]: "Киберпанк",
  ["demons"]: "Демоны",
  ["documentary"]: "Документальное",
  ["donghua"]: "Дунхуа",
  ["doujinshi"]: "Додзинси",
  ["drama"]: "Драма",
  ["early access"]: "Ранний доступ",
  ["ecchi"]: "Этти",
  ["education"]: "Образование",
  ["erotica"]: "Эротика",
  ["family"]: "Семейное",
  ["fantasy"]: "Фэнтези",
  ["fighting"]: "Файтинг",
  ["film noir"]: "Фильм-нуар",
  ["game show"]: "Игровое шоу",
  ["gender bender"]: "Смена пола",
  ["girls' love"]: "Сёдзё-ай",
  ["gore"]: "Жестокость",
  ["gourmet"]: "Кулинария",
  ["harem"]: "Гарем",
  ["hentai"]: "Хентай",
  ["historical"]: "Историческое",
  ["horror"]: "Ужасы",
  ["indie"]: "Инди",
  ["isekai"]: "Исекай",
  ["josei"]: "Дзёсэй",
  ["mahou shoujo"]: "Махо-сёдзё",
  ["martial arts"]: "Боевые искусства",
  ["mecha"]: "Меха",
  ["medical"]: "Медицина",
  ["music"]: "Музыка",
  ["mystery"]: "Детектив",
  ["news"]: "Новости",
  ["one-shot"]: "Ваншот",
  ["philosophical"]: "Философское",
  ["platformer"]: "Платформер",
  ["poetry"]: "Поэзия",
  ["political"]: "Политика",
  ["post-apocalyptic"]: "Постапокалиптика",
  ["programming & it"]: "Программирование",
  ["psychological"]: "Психологическое",
  ["puzzle"]: "Головоломка",
  ["racing"]: "Гонки",
  ["reality tv"]: "Реалити-шоу",
  ["religion"]: "Религия",
  ["romance"]: "Романтика",
  ["school"]: "Школа",
  ["sci-fi"]: "Фантастика",
  ["science"]: "Наука",
  ["seinen"]: "Сэйнэн",
  ["self-help"]: "Саморазвитие",
  ["shooter"]: "Шутер",
  ["short"]: "Короткометражка",
  ["shoujo"]: "Сёдзё",
  ["shounen"]: "Сёнэн",
  ["simulation"]: "Симулятор",
  ["slice of life"]: "Повседневность",
  ["space"]: "Космос",
  ["sports"]: "Спорт",
  ["steampunk"]: "Стимпанк",
  ["strategy"]: "Стратегия",
  ["superhero"]: "Супергерои",
  ["supernatural"]: "Сверхъестественное",
  ["survival"]: "Выживание",
  ["talk show"]: "Ток-шоу",
  ["thriller"]: "Триллер",
  ["tv movie"]: "ТВ-фильм",
  ["utilities & software"]: "Утилиты",
  ["vampire"]: "Вампиры",
  ["war"]: "Военное",
  ["web comic"]: "Веб-комикс",
  ["western"]: "Вестерн",
  ["work life"]: "Работа",
  ["zombies"]: "Зомби",
};

/** Localizes a canonical (or already-normalized) genre name; unknown genres pass through untouched. */
export function genreLabel(genre: string): string {
  const normalized = genre
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
  const key =
    ALIASES[normalized] ??
    normalized
      .replace(/\s+([a-z])/g, (_, letter: string) => letter.toUpperCase())
      .replace(/^([a-z])/, (_, letter: string) => letter.toLowerCase());
  if (key in i18n.t.stats.genres) {
    return i18n.t.stats.genres[key as keyof typeof i18n.t.stats.genres];
  }

  // No localized stats entry: fall back to the server genre dictionary (RU locale only —
  // the dictionary carries Russian names by design).
  return i18n.current === "ru" ? (RU_FALLBACKS[normalized] ?? RU_FALLBACKS[key] ?? genre) : genre;
}

/** Localizes a genre list and removes duplicates, so "Боевик, Боевик" never renders. */
export function formatGenresList(genres: readonly string[]): string[] {
  return [...new Set(genres.map((genre) => genreLabel(genre.trim())).filter(Boolean))];
}
