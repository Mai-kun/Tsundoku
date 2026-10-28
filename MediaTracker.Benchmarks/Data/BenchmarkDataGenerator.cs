using System.Text;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Benchmarks.Data;

/// <summary>Synthetic data for benchmark GlobalSetup. Deterministic enough to compare runs.</summary>
public static class BenchmarkDataGenerator
{
    private static readonly string[] GenrePool =
    [
        "Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror",
        "Mystery", "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural",
        "Thriller", "Psychological", "Historical",
    ];

    private static readonly string[] TitlePrefixes =
    [
        "Neon", "Silent", "Crimson", "Eternal", "Broken", "Golden",
        "Shadow", "Frozen", "Wild", "Last",
    ];

    private static readonly string[] TitleSubjects =
    [
        "Blade", "Chronicle", "Odyssey", "Garden", "Protocol", "Covenant",
        "Symphony", "Frontier", "Legend", "Paradox",
    ];

    public static List<MediaItem> Generate2000Items()
    {
        var items = new List<MediaItem>(2000);
        for (var i = 0; i < 2000; i++)
        {
            var title = $"{TitlePrefixes[i % TitlePrefixes.Length]} {TitleSubjects[(i / 10) % TitleSubjects.Length]} {i}";
            var genres = string.Join(',', GenrePool.Take(2 + (i % 4)));
            var year = 1960 + (i % 65);
            items.Add((i % 5) switch
            {
                0 => new Movie
                {
                    Title = title,
                    Genres = genres,
                    ReleaseYear = year,
                    DurationMinutes = 80 + (i % 100),
                    Director = $"Director {i % 50}",
                    Studio = $"Studio {i % 30}",
                    Score = i % 3 == 0 ? null : i % 10,
                    ExternalRating = i % 4 == 0 ? null : 4 + (i % 60) / 10.0,
                },
                1 => new TvShow
                {
                    Title = title,
                    Genres = genres,
                    ReleaseYear = year,
                    Network = $"Network {i % 20}",
                    Score = i % 3 == 0 ? null : i % 10,
                    ExternalRating = i % 4 == 0 ? null : 4 + (i % 60) / 10.0,
                },
                2 => new VideoGame
                {
                    Title = title,
                    Genres = genres,
                    ReleaseYear = year,
                    Platform = i % 2 == 0 ? "PC" : "PlayStation 5",
                    Studio = $"Studio {i % 30}",
                    HoursPlayed = i % 120,
                    Score = i % 3 == 0 ? null : i % 10,
                    ExternalRating = i % 4 == 0 ? null : 4 + (i % 60) / 10.0,
                },
                3 => new Book
                {
                    Title = title,
                    Genres = genres,
                    ReleaseYear = year,
                    Author = $"Author {i % 80}",
                    TotalPages = 150 + (i % 600),
                    CurrentPage = i % 300,
                    Score = i % 3 == 0 ? null : i % 10,
                    ExternalRating = i % 4 == 0 ? null : 4 + (i % 60) / 10.0,
                },
                _ => new Manga
                {
                    Title = title,
                    Genres = genres,
                    ReleaseYear = year,
                    Author = $"Mangaka {i % 80}",
                    TotalChapters = 20 + (i % 400),
                    CurrentChapter = i % 150,
                    TotalVolumes = 3 + (i % 25),
                    Score = i % 3 == 0 ? null : i % 10,
                    ExternalRating = i % 4 == 0 ? null : 4 + (i % 60) / 10.0,
                },
            });
        }
        return items;
    }

    public static SmartListQueryDto GenerateComplexSmartListQuery() => new()
    {
        Statuses = [],
        MinScore = 3,
        MaxScore = 9,
        MinExternalRating = 5.0,
        Genres = ["Action", "Drama"],
        ReleaseYearFrom = 1990,
        ReleaseYearTo = 2020,
        MaxDurationMinutes = 180,
        MaxEpisodes = 40,
        MaxPages = 800,
        MaxChapters = 300,
        SortBy = "score",
        SortOrder = "desc",
        Limit = 100,
    };

    public static (MediaItem Item, List<ExternalMediaDto> Candidates, List<string> Priorities) GenerateMatchCandidates()
    {
        var item = new Movie
        {
            Title = "Neon Blade Chronicle",
            OriginalTitle = "Neon Blade Chronicle",
            ReleaseYear = 2015,
            Genres = "Action,Sci-Fi",
            Director = "Director 7",
        };

        var candidates = new List<ExternalMediaDto>();
        for (var i = 0; i < 10; i++)
        {
            candidates.Add(new ExternalMediaDto
            {
                ExternalId = $"ext-{i}",
                Title = i == 2 ? "Neon Blade Chronicle" : $"Neon Blade Chronicle {(char)('I' + i)}",
                OriginalTitle = i == 2 ? "Neon Blade Chronicle" : $"Neon Blade Chronicle {(char)('I' + i)}",
                Type = "movie",
                ReleaseYear = 2010 + i,
                Genres = ["Action", "Sci-Fi"],
                Studio = $"Studio {i}",
                Ratings = [new ExternalRatingDto { Source = "tmdb", Rating = 6 + i / 10.0, Votes = 1000 * i }],
            });
        }

        var priorities = new List<string> { "tmdb", "imdb", "anilist", "mal" };
        return (item, candidates, priorities);
    }

    public static List<string> GenerateRawGenresList()
    {
        var raw = new List<string>(30);
        foreach (var genre in GenrePool)
        {
            raw.Add(genre);
            raw.Add(genre.ToUpperInvariant());
            raw.Add(genre.ToLowerInvariant().Replace(" ", "").Replace("-", ""));
        }
        raw.Add("SciFi");
        raw.Add("Psycological");
        raw.Add("Slice-of-Life");
        return raw;
    }

    /// <summary>MangaLib bookmark-style JSON with 100 entries.</summary>
    public static string GenerateMangalib100Json()
    {
        var sb = new StringBuilder(64 * 1024);
        sb.Append('[');
        for (var i = 0; i < 100; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append($$"""
                {"site_id": 1, "type": "manga", "name": "Benchmark Manga {{i}}", "rus_name": "Бенчмарк Манга {{i}}", "status_id": {{i % 4 + 1}}, "created_at": "2024-01-01T00:00:00Z"}
                """);
        }
        sb.Append(']');
        return sb.ToString();
    }

    /// <summary>Generic CSV export with 100 data rows.</summary>
    public static string GenerateCsv100Rows()
    {
        var sb = new StringBuilder(16 * 1024);
        sb.AppendLine("title,status,score,notes,type");
        for (var i = 0; i < 100; i++)
        {
            sb.AppendLine($"\"CSV Item {i}\",Completed,{i % 10},\"Note, with comma {i}\",book");
        }
        return sb.ToString();
    }
}
