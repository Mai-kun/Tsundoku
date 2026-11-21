/// 1:1 port of `mediatracker-ui/src/entities/media/model/genreLabel.ts`.
///
/// Локализация жанров: алиасы → i18n stats.genres → RU-фолбэк словаря сервера.
library;

import '../../../shared/i18n/index.dart';

/// Canonical genre keys (camelCase translations keys from stats.genres) whose
/// natural camelCasing from the Title Case genre name does not produce the
/// key.
const Map<String, String> _aliases = <String, String>{
  'sci fi': 'sciFi',
  'slice of life': 'sliceOfLife',
  'game show': 'gameShow',
  'talk show': 'talkShow',
  'martial arts': 'martialarts',
  'board & card': 'boardAndCard',
  'board and card': 'boardAndCard',
  'utilities & software': 'utilitiesAndSoftware',
  'utilities and software': 'utilitiesAndSoftware',
  'programming & it': 'programmingAndIt',
  'programming and it': 'programmingAndIt',
  'business & economics': 'businessAndEconomics',
  'business and economics': 'businessAndEconomics',
  'art & design': 'artAndDesign',
  'art and design': 'artAndDesign',
  // Legacy canonical names still stored in old rows of tracker.db
  'reality': 'realityTv',
  'kids': 'family',
};

/// Dictionary-driven Russian fallbacks (generated from
/// MediaTracker.Server/Resources/genres-dictionary.json). Used when the i18n
/// catalog has no entry for the canonical name — offline imports can carry
/// genres the stats translations never heard of (e.g. "Donghua").
const Map<String, String> _ruFallbacks = <String, String>{
  'action': 'Боевик',
  'adventure': 'Приключения',
  'animals': 'Животные',
  'animation': 'Анимация',
  'arcade': 'Аркада',
  'art & design': 'Искусство и дизайн',
  'biography': 'Биография',
  'board & card': 'Настольные игры',
  "boys' love": 'Сёнэн-ай',
  'business & economics': 'Бизнес и экономика',
  'casual': 'Казуальная игра',
  'comedy': 'Комедия',
  'crime': 'Криминал',
  'cyberpunk': 'Киберпанк',
  'demons': 'Демоны',
  'documentary': 'Документальное',
  'donghua': 'Дунхуа',
  'doujinshi': 'Додзинси',
  'drama': 'Драма',
  'early access': 'Ранний доступ',
  'ecchi': 'Этти',
  'education': 'Образование',
  'erotica': 'Эротика',
  'family': 'Семейное',
  'fantasy': 'Фэнтези',
  'fighting': 'Файтинг',
  'film noir': 'Фильм-нуар',
  'game show': 'Игровое шоу',
  'gender bender': 'Смена пола',
  "girls' love": 'Сёдзё-ай',
  'gore': 'Жестокость',
  'gourmet': 'Кулинария',
  'harem': 'Гарем',
  'hentai': 'Хентай',
  'historical': 'Историческое',
  'horror': 'Ужасы',
  'indie': 'Инди',
  'isekai': 'Исекай',
  'josei': 'Дзёсэй',
  'mahou shoujo': 'Махо-сёдзё',
  'martial arts': 'Боевые искусства',
  'mecha': 'Меха',
  'medical': 'Медицина',
  'music': 'Музыка',
  'mystery': 'Детектив',
  'news': 'Новости',
  'one-shot': 'Ваншот',
  'philosophical': 'Философское',
  'platformer': 'Платформер',
  'poetry': 'Поэзия',
  'political': 'Политика',
  'post-apocalyptic': 'Постапокалиптика',
  'programming & it': 'Программирование',
  'psychological': 'Психологическое',
  'puzzle': 'Головоломка',
  'racing': 'Гонки',
  'reality tv': 'Реалити-шоу',
  'religion': 'Религия',
  'romance': 'Романтика',
  'school': 'Школа',
  'sci-fi': 'Фантастика',
  'science': 'Наука',
  'seinen': 'Сэйнэн',
  'self-help': 'Саморазвитие',
  'shooter': 'Шутер',
  'short': 'Короткометражка',
  'shoujo': 'Сёдзё',
  'shounen': 'Сёнэн',
  'simulation': 'Симулятор',
  'slice of life': 'Повседневность',
  'space': 'Космос',
  'sports': 'Спорт',
  'steampunk': 'Стимпанк',
  'strategy': 'Стратегия',
  'superhero': 'Супергерои',
  'supernatural': 'Сверхъестественное',
  'survival': 'Выживание',
  'talk show': 'Ток-шоу',
  'thriller': 'Триллер',
  'tv movie': 'ТВ-фильм',
  'utilities & software': 'Утилиты',
  'vampire': 'Вампиры',
  'war': 'Военное',
  'web comic': 'Веб-комикс',
  'western': 'Вестерн',
  'work life': 'Работа',
  'zombies': 'Зомби',
};

/// Localizes a canonical (or already-normalized) genre name; unknown genres
/// pass through untouched.
String genreLabel(String genre, I18nDictionary t, Locale locale) {
  final normalized = genre
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  final key = _aliases[normalized] ??
      normalized
          .replaceAllMapped(
            RegExp(r'\s+([a-z])'),
            (m) => m.group(1)!.toUpperCase(),
          )
          .replaceFirstMapped(
            RegExp(r'^([a-z])'),
            (m) => m.group(1)!.toLowerCase(),
          );
  try {
    return t.tr('stats.genres.$key');
  } on ArgumentError {
    // No localized stats entry: fall back to the server genre dictionary
    // (RU locale only — the dictionary carries Russian names by design).
  }
  return locale == Locale.ru
      ? (_ruFallbacks[normalized] ?? _ruFallbacks[key] ?? genre)
      : genre;
}

/// Localizes a genre list and removes duplicates, so «Боевик, Боевик» never
/// renders.
List<String> formatGenresList(
    Iterable<String> genres, I18nDictionary t, Locale locale) {
  final seen = <String>{};
  final out = <String>[];
  for (final genre in genres) {
    final label = genreLabel(genre.trim(), t, locale);
    if (label.isNotEmpty && seen.add(label)) {
      out.add(label);
    }
  }
  return out;
}
