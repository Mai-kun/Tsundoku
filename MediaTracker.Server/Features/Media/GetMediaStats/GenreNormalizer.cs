namespace MediaTracker.Server.Features.Media.GetMediaStats;

/// <summary>
/// Maps provider-specific genre names to a stable English canonical genre name.
/// The registry covers every spelling our providers emit (AniList, Kitsu, MangaDex, MangaUpdates,
/// Shikimori, Simkl, IMDb, Kinopoisk, TMDb, RAWG, Steam, OpenLibrary); an alias that is not in the
/// dictionary survives as a trimmed original string instead of being dropped.
/// </summary>
public static class GenreNormalizer
{
    private static readonly Dictionary<string, string> Aliases = BuildAliases();

    public static string Normalize(string rawGenre)
    {
        var value = rawGenre.Trim();
        if (value.Length == 0)
        {
            return value;
        }

        var key = string.Join(' ', value.ToLowerInvariant().Replace('-', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return Aliases.GetValueOrDefault(key, value);
    }

    public static IEnumerable<string> ExtractGenres(string? genresRaw)
    {
        if (string.IsNullOrWhiteSpace(genresRaw)) yield break;
        var raw = genresRaw.Trim();
        if (raw.StartsWith('[') && raw.EndsWith(']'))
        {
            List<string>? list = null;
            try
            {
                list = global::System.Text.Json.JsonSerializer.Deserialize<List<string>>(raw);
            }
            catch
            {
                // Fall back to delimiter-based splitting if not valid JSON
            }

            if (list != null)
            {
                foreach (var g in list)
                {
                    if (!string.IsNullOrWhiteSpace(g))
                    {
                        var trimmed = g.Trim().Trim('"', '\'');
                        if (!string.IsNullOrWhiteSpace(trimmed))
                        {
                            yield return trimmed;
                        }
                    }
                }
                yield break;
            }
        }

        var parts = raw.Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var part in parts)
        {
            var cleaned = part.Trim().Trim('[', ']', '"', '\'', ' ');
            if (!string.IsNullOrWhiteSpace(cleaned))
            {
                yield return cleaned;
            }
        }
    }

    /// <summary>Normalizes each entry, drops blanks and dedupes (case-insensitive), preserving order.</summary>
    public static IReadOnlyList<string> NormalizeList(IEnumerable<string>? rawGenres)
    {
        if (rawGenres is null)
        {
            return [];
        }

        return rawGenres
            .Select(Normalize)
            .Where(g => !string.IsNullOrWhiteSpace(g))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>Splits, normalizes, dedupes and re-joins a genre list; null when nothing remains.</summary>
    public static string? NormalizeToCommaString(IEnumerable<string>? rawGenres)
    {
        var genres = NormalizeList(rawGenres);
        return genres.Count > 0 ? string.Join(", ", genres) : null;
    }

    public static string? NormalizeToCommaString(string? rawCommaSeparated)
    {
        if (string.IsNullOrWhiteSpace(rawCommaSeparated))
        {
            return null;
        }

        return NormalizeToCommaString(ExtractGenres(rawCommaSeparated));
    }

    private static Dictionary<string, string> BuildAliases()
    {
        var aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        void Add(string canonical, params string[] values)
        {
            foreach (var alias in values.Append(canonical))
            {
                var key = string.Join(' ', alias.ToLowerInvariant().Replace('-', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries));
                aliases[key] = canonical;
            }
        }

        // Basic film/series/anime/manga
        Add("Action", "action", "боевик", "экшен", "экшн", "экшены", "действие", "приключенческий боевик", "action epic", "b-action", "car action", "gun fu", "one-person army", "jason statham action", "swashbuckler");
        Add("Adventure", "adventure", "приключения", "приключение", "приключенческий", "приключенческие игры", "adventure epic", "animal adventure", "desert adventure", "dinosaur adventure", "globetrotting adventure", "jungle adventure", "mountain adventure", "sea adventure", "urban adventure", "quest", "road trip", "sword & sandal");
        Add("Comedy", "comedy", "комедия", "комедийный", "юмор", "dark comedy", "farce", "high-concept comedy", "holiday comedy", "parody", "пародия", "quirky comedy", "raunchy comedy", "screwball comedy", "sitcom", "sketch comedy", "slapstick", "stand-up", "стендап", "stoner comedy", "teen comedy", "body swap comedy", "buddy comedy");
        Add("Drama", "drama", "драма", "романы", "пьесы", "рассказы", "classic", "классика", "coming-of-age", "cop drama", "costume drama", "docudrama", "financial drama", "korean drama", "legal drama", "medical drama", "period drama", "political drama", "prison drama", "psychological drama", "showbiz drama", "soap opera", "teen drama", "telenovela", "tragedy", "трагедия", "workplace drama");
        Add("Sci-Fi", "sci-fi", "sci fi", "science fiction", "science-fiction", "science-fiction (sci-fi)", "sci-fi & fantasy", "научная фантастика", "фантастика", "научно-фантастический", "sci-fi epic", "dystopian sci-fi", "space sci-fi", "artificial intelligence", "alien invasion", "aliens", "пришельцы", "инопланетяне", "virtual reality", "виртуальная реальность", "time travel", "путешествия во времени");
        Add("Fantasy", "fantasy", "фэнтези", "фентези", "dark fantasy", "fairy tale", "сказка", "fantasy epic", "supernatural fantasy", "sword & sorcery", "teen fantasy", "magic", "магия", "monster girls", "девушки-монстры");
        Add("Romance", "romance", "романтика", "романс", "мелодрама", "любовь", "dark romance", "feel-good romance", "holiday romance", "romantic comedy", "ромком", "romantic epic", "steamy romance", "teen romance", "tragic romance");
        Add("Thriller", "thriller", "триллер", "триллеры", "саспенс", "suspense", "suspense / thriller", "conspiracy thriller", "cyber thriller", "erotic thriller", "legal thriller", "political thriller", "psychological thriller");
        Add("Horror", "horror", "ужасы", "хоррор", "b-horror", "body horror", "folk horror", "found footage horror", "monster horror", "monsters", "монстры", "psychological horror", "slasher horror", "splatter horror", "supernatural horror", "teen horror", "vampire horror", "werewolf horror", "witch horror", "zombie horror", "ghosts", "призраки");
        Add("Mystery", "mystery", "детектив", "мистика", "тайна", "мистика и детективы", "bumbling detective", "cozy mystery", "hard-boiled detective", "suspense mystery", "whodunit");
        Add("Slice of Life", "slice of life", "повседневность", "повседневная жизнь", "быт", "iyashikei", "социальной жизнь и обычаи", "социальная жизнь и обычаи", "lifestyle");
        Add("Supernatural", "supernatural", "сверхъестественное", "сверхъестественные силы");
        Add("Psychological", "psychological", "психологическое", "психологический", "психология", "dementia", "безумие");
        Add("Philosophical", "philosophical", "философия");
        Add("Historical", "historical", "history", "история", "исторический", "художественная история", "historical epic", "древние цивилизации", "археология", "короли и правители");
        Add("Crime", "crime", "криминал", "преступление", "caper", "drug crime", "gangster", "heist", "police", "police procedural", "полиция", "полицейский", "true crime", "mafia", "мафия", "delinquents", "хулиганы", "serial killer");
        Add("War", "war", "война", "военный", "военное", "military", "war epic", "вторая мировая война");
        Add("Western", "western", "вестерн", "classical western", "contemporary western", "spaghetti western", "western epic");
        Add("Animation", "animation", "анимация", "мультфильм", "adult animation", "computer animation", "hand-drawn animation", "stop motion animation", "holiday animation", "anime influenced");
        Add("Documentary", "documentary", "документальный", "документальное кино", "crime documentary", "docuseries", "faith & spirituality documentary", "food documentary", "history documentary", "military documentary", "music documentary", "nature documentary", "political documentary", "science & technology documentary", "sports documentary", "travel documentary", "mockumentary");
        Add("Family", "family", "семейный", "семья", "holiday family", "kids", "детский", "для детей", "детские книги", "книжки-малышки", "книги на ночь", "книги с картинками");
        Add("Sports", "sports", "sport", "спорт", "спортивный", "baseball", "basketball", "boxing", "extreme sport", "football", "soccer", "water sport", "упражнения");
        Add("Music", "music", "музыка", "музыкальный", "musical", "мюзикл", "music / musical", "classical musical", "concert", "концерт", "jukebox musical", "pop musical", "rock musical", "теория музыки", "композиторы");
        Add("Biography", "biography", "биография", "автобиографии");
        Add("Film Noir", "film noir", "фильм-нуар", "giallo");
        Add("Cyberpunk", "cyberpunk", "киберпанк");
        Add("Steampunk", "steampunk", "стимпанк");
        Add("Post-Apocalyptic", "post-apocalyptic", "постапокалипсис", "постапокалиптика", "disaster", "катастрофа");
        Add("Survival", "survival", "выживание");
        Add("Superhero", "superhero", "супергерои", "super power", "суперсила", "суперсилы", "tokusatsu", "токусацу");
        Add("Mecha", "mecha", "меха", "механика", "kaiju", "кайдзю");
        Add("Mahou Shoujo", "mahou shoujo", "махо-сёдзё", "magical girls", "magical girl (mahou shoujo)", "mahou shounen");
        Add("Isekai", "isekai", "исекай", "попаданцы", "reincarnation", "реинкарнация", "перерождение", "villainess", "злодейка");
        Add("Martial Arts", "martial arts", "боевые искусства", "кунг-фу", "kung fu", "wuxia", "уся", "samurai", "самураи", "ninja", "ниндзя");
        Add("School", "school", "school life", "школа", "школьная жизнь", "youth", "молодёжь", "подростковая литература", "teen adventure");
        Add("Work Life", "work life", "workplace", "office workers", "работа", "офис");
        Add("Gourmet", "gourmet", "гурман", "еда", "кулинария", "cooking", "food", "cooking & food", "приготовление еды", "поваренные книги", "питание");
        Add("Medical", "medical", "медицина", "медицинский", "душевное здоровье");
        Add("Political", "political", "политика", "политический", "политика и правительство", "политическая наука", "law", "право");
        Add("Space", "space", "космос");
        Add("Vampire", "vampire", "vampires", "вампиры");
        Add("Demons", "demons", "демоны");
        Add("Zombies", "zombies", "зомби");
        Add("Animals", "animals", "животные", "медведи", "кошки", "котята", "собаки", "щенки");
        Add("Harem", "harem", "гарем", "reverse harem", "обратный гарем");
        Add("Ecchi", "ecchi", "этти", "ecchi / harem");
        Add("Erotica", "erotica", "эротика", "smut", "mature", "adult", "для взрослых", "sexual violence", "incest", "lolicon", "loli", "shotacon", "shota");
        Add("Hentai", "hentai", "хентай");
        Add("Gore", "gore", "жестокость", "гуро");
        Add("Boys' Love", "boys' love", "yaoi", "яой", "shounen ai", "сёнен-ай", "сёнэн-ай");
        Add("Girls' Love", "girls' love", "yuri", "юри", "shoujo ai", "сёдзё-ай");
        Add("Gender Bender", "gender bender", "genderswap", "crossdressing", "гендерная интрига", "смена пола");
        Add("Shounen", "shounen", "shonen", "shōnen", "сёнэн", "сёунэн");
        Add("Seinen", "seinen", "сэйнэн", "сэйнен");
        Add("Shoujo", "shoujo", "shojo", "shōjo", "сёдзё", "сёдзе");
        Add("Josei", "josei", "дзёсэй", "дзесей");
        Add("Doujinshi", "doujinshi", "додзинси", "self-published");
        Add("Web Comic", "web comic", "веб-комикс", "long strip", "full color", "official colored", "fan colored", "anthology", "антология", "oneshot", "ваншот", "adaptation", "адаптация", "award winning", "gyaru", "гяру");

        // TV formats
        Add("Reality TV", "reality", "reality tv", "reality-tv", "реальное тв", "реалити", "реалити-шоу", "business reality tv", "crime reality tv", "dating reality tv", "docusoap reality tv", "paranormal reality tv", "beauty competition", "beauty makeover", "cooking competition", "home improvement", "survival competition", "talent competition", "hidden camera");
        Add("Game Show", "game show", "игровое шоу", "quiz show");
        Add("Talk Show", "talk show", "ток-шоу", "церемония");
        Add("News", "news", "новости");
        Add("Short", "short", "короткометражка", "короткометражный");
        Add("TV Movie", "tv movie", "телевизионный фильм", "holiday");

        // Video games (RAWG, Steam)
        Add("RPG", "rpg", "ролевые игры", "ролевая игра");
        Add("Shooter", "shooter", "шутер", "шутеры");
        Add("Strategy", "strategy", "стратегии", "стратегия");
        Add("Simulation", "simulation", "симуляторы", "симулятор");
        Add("Puzzle", "puzzle", "головоломки", "головоломка");
        Add("Platformer", "platformer", "платформер", "платформеры");
        Add("Fighting", "fighting", "файтинг", "файтинги");
        Add("Racing", "racing", "гонки", "cars", "автогонки", "тачки", "motorsport");
        Add("Arcade", "arcade", "аркада", "аркады");
        Add("Indie", "indie", "инди", "независимое кино");
        Add("Casual", "casual", "казуальные игры", "казуальная");
        Add("MMO", "massively multiplayer", "многопользовательские игры", "mmo", "mmorpg");
        Add("Board & Card", "board games", "card", "настольные игры", "карточные игры", "traditional games", "mahjong", "маджонг", "game", "игра", "video games", "видеоигры");
        Add("Free to Play", "free to play", "бесплатные");
        Add("Early Access", "early access", "ранний доступ");
        Add("Utilities & Software", "utilities", "утилиты", "accounting", "бухгалтерия", "audio production", "работа со звуком", "photo editing", "обработка фото", "software training", "обучение работе с по", "video production", "создание видео", "web publishing", "веб-разработка", "controller-friendly", "с поддержкой контроллеров", "macos", "steamos + linux", "steamos и linux", "demos", "демоверсии");

        // Books and non-fiction (OpenLibrary)
        Add("Poetry", "поэзия", "стихи", "poetry");
        Add("Art & Design", "архитектура", "руководства по искусству", "история искусства", "танцы", "дизайн", "мода", "кинематограф", "графический дизайн", "изобразительное искусство", "фотография", "художники");
        Add("Science", "биология", "химия", "математика", "алгебра", "физика", "естествознание", "география", "антропология");
        Add("Programming & IT", "программирование", "информатика");
        Add("Business & Economics", "менеджмент", "предпринимательство", "экономика", "успешные проекты", "финансы", "бизнес и экономика");
        Add("Education", "education", "educational", "образование", "английский язык", "английский", "русский");
        Add("Self-Help", "самопомощь", "self-help");
        Add("Religion", "религия", "religion");

        return aliases;
    }
}
