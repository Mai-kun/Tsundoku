using System.Globalization;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class LetterboxdCsvParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string csv) => CsvHelperMini.ReadRecords(csv).Select(row =>
    {
        var name = Get(row, "Name", "Title");
        int? year = int.TryParse(Get(row, "Year"), out var y) ? y : null;
        int? score = double.TryParse(Get(row, "Rating"), NumberStyles.Number, CultureInfo.InvariantCulture, out var rating)
            ? (int?)Math.Clamp((int)Math.Round(rating * 2, MidpointRounding.AwayFromZero), 1, 10) : null;
        DateTime? watched = DateTime.TryParse(Get(row, "Watched Date"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date : null;
        return new ParsedMediaItemDto(name, "movie", MediaStatus.Completed, score, ReleaseYear: year, WatchedAt: watched, ExternalId: Get(row, "Letterboxd URI"), ExternalSource: "letterboxd");
    }).Where(item => !string.IsNullOrWhiteSpace(item.Title)).ToArray();

    private static string Get(Dictionary<string, string> row, params string[] keys) => keys.Select(key => row.GetValueOrDefault(key, "")).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";
}
