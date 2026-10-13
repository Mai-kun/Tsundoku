using System.Globalization;
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
        return new ParsedMediaItemDto(title, type, Status(Get(row, "status", "статус")),
            Number(row, "score", "rating", "оценка") is { } score and > 0 ? Math.Clamp(score, 1, 10) : null,
            CurrentProgress: Number(row, "progress", "прогресс"),
            TotalCount: Number(row, "totalcount", "total_count", "всего"),
            Author: Get(row, "author", "studio", "director", "автор", "студия", "режиссёр"),
            ReleaseYear: Number(row, "releaseyear", "year", "год"));
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
}