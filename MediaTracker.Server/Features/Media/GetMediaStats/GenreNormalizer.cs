namespace MediaTracker.Server.Features.Media.GetMediaStats;

/// <summary>Maps provider-specific genre names to a stable English genre name.</summary>
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

    private static Dictionary<string, string> BuildAliases()
    {
        var aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        Add("Action", "action", "бoeвик", "боевик", "экшен", "экшн", "действие", "приключенческий боевик");
        Add("Drama", "drama", "драма");
        Add("Adventure", "adventure", "приключения", "приключение", "приключенческий");
        Add("Sci-Fi", "sci fi", "science fiction", "sci-fi", "sci fi & fantasy", "научная фантастика", "фантастика", "научно-фантастический");
        Add("Fantasy", "fantasy", "фэнтези", "фентези");
        Add("Comedy", "comedy", "комедия", "комедийный");
        Add("Romance", "romance", "романтика", "романс", "мелодрама", "любовь");
        Add("Thriller", "thriller", "триллер", "саспенс");
        Add("Horror", "horror", "ужасы", "хоррор");
        Add("Mystery", "mystery", "детектив", "мистика", "тайна");
        Add("Slice of Life", "slice of life", "повседневность", "повседневная жизнь", "быт");
        Add("Supernatural", "supernatural", "сверхъестественное", "сверхъестественные силы");
        Add("Animation", "animation", "анимация", "мультфильм");
        Add("Crime", "crime", "криминал", "преступление");
        Add("Family", "family", "семейный", "семья");
        Add("War", "war", "война", "военный");
        Add("Sports", "sports", "спорт", "спортивный");
        Add("Mecha", "mecha", "меха", "механика");
        Add("Music", "music", "музыка", "музыкальный");
        Add("Psychological", "psychological", "психологический", "психология");
        Add("Historical", "historical", "исторический", "история");
        Add("Documentary", "documentary", "документальный", "документальное кино");
        Add("Western", "western", "вестерн");
        Add("Isekai", "isekai", "исекай", "попаданцы");
        Add("Shounen", "shounen", "shonen", "сёунэн", "сёнэн", "shōnen");
        Add("Seinen", "seinen", "сэйнэн", "сэйнен");
        Add("Shoujo", "shoujo", "shojo", "сёдзё", "сёдзе", "shōjo");
        Add("Ecchi", "ecchi", "этти");
        Add("Hentai", "hentai", "хентай");
        Add("Game Show", "game show", "игровое шоу");
        Add("Reality", "reality", "реалити");
        Add("Talk Show", "talk show", "ток-шоу");
        Add("News", "news", "новости");
        Add("Kids", "kids", "детский", "для детей");
        return aliases;

        void Add(string canonical, params string[] values)
        {
            foreach (var alias in values.Append(canonical))
            {
                var key = string.Join(' ', alias.ToLowerInvariant().Replace('-', ' ').Split(' ', StringSplitOptions.RemoveEmptyEntries));
                aliases[key] = canonical;
            }
        }
    }
}
