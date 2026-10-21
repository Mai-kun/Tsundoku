using System.Globalization;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class GoodreadsCsvParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string csv) => CsvHelperMini.ReadRecords(csv).Select(row =>
    {
        var shelf = Get(row, "Exclusive Shelf").ToLowerInvariant();
        var status = shelf switch { "read" => MediaStatus.Completed, "currently-reading" => MediaStatus.InProgress, _ => MediaStatus.Planned };
        var rating = int.TryParse(Get(row, "My Rating"), out var stars) && stars is >= 1 and <= 5 ? stars * 2 : (int?)null;
        return new ParsedMediaItemDto(Get(row, "Title"), "book", status, rating,
            TotalCount: Number(row, "Number of Pages"), Author: Get(row, "Author"), ExternalId: Get(row, "Book Id"), ExternalSource: "goodreads");
    }).Where(item => !string.IsNullOrWhiteSpace(item.Title)).ToArray();

    private static string Get(Dictionary<string,string> row, string key) => row.GetValueOrDefault(key, "");
    private static int? Number(Dictionary<string,string> row, string key) => int.TryParse(Get(row,key), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : null;
}
