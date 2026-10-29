using System.Globalization;
using MediaTracker.Server.Common.Utilities;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

/// <summary>
/// Universal import for user-made JSON/CSV files. Column names and values are matched
/// case-insensitively with Russian aliases, so the template is a suggestion rather than a contract.
/// Rows without a title or a resolvable type are skipped instead of failing the whole import.
/// </summary>
public static class CustomImportParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string content) => CsvHelperMini.ReadAnyRecords(content)
        .Select(Map)
        .OfType<ParsedMediaItemDto>()
        .ToArray();

    private static ParsedMediaItemDto? Map(Dictionary<string, string> row)
    {
        var title = Get(row, "title", "name", "название");
        var type = Type(Get(row, "type", "тип"));
        if (string.IsNullOrWhiteSpace(title) || type is null) return null;

        var author = NullIfEmpty(Get(row, "author", "автор", "artist", "creator"));
        var studio = NullIfEmpty(Get(row, "studio", "студия", "developer", "разработчик", "publisher"));
        var director = NullIfEmpty(Get(row, "director", "режиссёр", "режиссер"));
        var effectiveAuthor = author ?? director ?? studio;

        var cover = NullIfEmpty(Get(row, "coverurl", "cover_url", "cover", "image", "poster", "обложка"));
        var desc = NullIfEmpty(Get(row, "description", "summary", "desc", "синопсис", "описание"));
        var genres = NullIfEmpty(Get(row, "genres", "genre", "жанры", "жанр"));
        var releaseDate = NullIfEmpty(Get(row, "releasedate", "release_date", "дата_выхода", "датавыхода"));
        var endDate = NullIfEmpty(Get(row, "enddate", "end_date", "дата_окончания", "датаокончания"));
        var releaseStatus = NullIfEmpty(Get(row, "releasestatus", "release_status", "статус_релиза", "статусрелиза"));
        var romaji = NullIfEmpty(Get(row, "romaji", "romaji_title", "romajititle", "english_title", "eng_name"));

        var rating = Double(row, "rating", "external_rating", "externalrating", "рейтинг");
        var score = Number(row, "score", "оценка");
        if (score is null && rating is { } r and >= 1 and <= 10)
        {
            score = (int)Math.Round(r);
        }

        var year = Number(row, "releaseyear", "year", "год") ?? ParseYear(releaseDate);

        return new ParsedMediaItemDto(
            Title: title,
            Type: type,
            Status: Status(Get(row, "status", "статус")),
            Score: score is > 0 ? Math.Clamp(score.Value, 1, 10) : null,
            CurrentProgress: Number(row, "progress", "прогресс"),
            TotalCount: Number(row, "totalcount", "total_count", "всего"),
            Author: effectiveAuthor,
            ReleaseYear: year,
            CoverUrl: cover,
            Description: desc,
            Genres: genres,
            ReleaseDate: releaseDate,
            EndDate: endDate,
            ReleaseStatus: releaseStatus,
            RomajiTitle: romaji,
            Rating: rating,
            Studio: studio,
            Director: director);
    }

    private static string? Type(string value) => value.Trim().ToLowerInvariant() switch
    {
        "game" or "games" or "игра" or "игры" => "game",
        "movie" or "film" or "фильм" or "фильмы" => "movie",
        "tvshow" or "tv" or "show" or "сериал" or "сериалы" => "tvshow",
        "anime" or "аниме" => "anime",
        "manga" or "манга" => "manga",
        "book" or "books" or "книга" or "книги" => "book",
        _ => null
    };

    private static MediaStatus Status(string value)
    {
        var normalized = value.Trim().ToLowerInvariant().Replace(' ', '_').Replace('-', '_');
        if (int.TryParse(normalized, NumberStyles.Integer, CultureInfo.InvariantCulture, out var code) && code is >= 0 and <= 4)
            return (MediaStatus)code;
        return normalized switch
        {
            "completed" or "прочитано" or "завершено" or "просмотрено" => MediaStatus.Completed,
            "in_progress" or "inprogress" or "watching" or "reading" or "в_процессе" or "смотрю" or "читаю" => MediaStatus.InProgress,
            "on_hold" or "onhold" or "отложено" => MediaStatus.OnHold,
            "dropped" or "брошено" or "дропнуто" => MediaStatus.Dropped,
            _ => MediaStatus.Planned
        };
    }

    private static string Get(Dictionary<string, string> row, params string[] keys) =>
        keys.Select(key => row.GetValueOrDefault(key, "")).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";

    private static int? Number(Dictionary<string, string> row, params string[] keys) =>
        int.TryParse(Get(row, keys), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : null;

    private static double? Double(Dictionary<string, string> row, params string[] keys) =>
        double.TryParse(Get(row, keys), NumberStyles.Float, CultureInfo.InvariantCulture, out var n) ? n : null;

    private static string? NullIfEmpty(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
        ? date.Year
        : SpanParserExtensions.ParseYearFromDateString(value.AsSpan().Trim());
}