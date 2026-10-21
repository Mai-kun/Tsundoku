using System.Globalization;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

/// <summary>
/// Tampermonkey scripts and browser extensions for MangaLib export either JSON or CSV with a mix of
/// numeric status codes and Russian status words, so both shapes map through the same row reader.
/// </summary>
public static class MangalibParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string content) => CsvHelperMini.ReadAnyRecords(content)
        .Select(Map)
        .Where(item => !string.IsNullOrWhiteSpace(item.Title))
        .ToArray();

    private static ParsedMediaItemDto Map(Dictionary<string, string> row)
    {
        var progress = Number(row, "user_chapters", "read_chapters", "chapters_read", "chapter");
        var cover = NullIfEmpty(Get(row, "cover", "img", "poster", "thumbnail", "image", "cover_url"));
        var description = NullIfEmpty(Get(row, "summary", "description", "desc", "синопсис", "описание"));
        var genres = NullIfEmpty(Get(row, "genres", "genre", "жанры", "жанр"));
        var author = NullIfEmpty(Get(row, "author", "authors", "автор", "авторы", "artist"));
        var romaji = NullIfEmpty(Get(row, "eng_name", "romaji", "romaji_name"));

        return new ParsedMediaItemDto(
            Title: Get(row, "rus_name", "name", "eng_name", "title"),
            Type: "manga",
            Status: Status(Get(row, "status")),
            Score: Score(Number(row, "user_rating", "rating", "score")),
            CurrentProgress: progress ?? 0,
            TotalCount: Number(row, "chapters", "total_chapters"),
            Author: author,
            ExternalSource: "MangaLib",
            CoverUrl: cover,
            Description: description,
            Genres: genres,
            RomajiTitle: romaji);
    }

    private static string? NullIfEmpty(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static MediaStatus Status(string value)
    {
        if (int.TryParse(value.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var code)) return code switch
        {
            1 => MediaStatus.InProgress,
            2 => MediaStatus.Planned,
            3 => MediaStatus.Dropped,
            4 or 5 => MediaStatus.Completed,
            6 => MediaStatus.OnHold,
            _ => MediaStatus.Planned
        };
        return value.Trim().ToLowerInvariant() switch
        {
            "читаю" => MediaStatus.InProgress,
            "прочитано" or "любимое" or "любимые" => MediaStatus.Completed,
            "брошено" => MediaStatus.Dropped,
            "отложено" => MediaStatus.OnHold,
            _ => MediaStatus.Planned
        };
    }

    private static int? Score(int? value) => value is > 0 ? Math.Clamp(value.Value, 1, 10) : null;

    private static string Get(Dictionary<string, string> row, params string[] keys) =>
        keys.Select(key => row.GetValueOrDefault(key, "")).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";

    private static int? Number(Dictionary<string, string> row, params string[] keys) =>
        int.TryParse(Get(row, keys), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : null;
}