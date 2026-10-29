using System.Globalization;
using System.Xml.Linq;
using MediaTracker.Server.Common.Utilities;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class MalXmlParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string xml, bool manga)
    {
        var document = XDocument.Parse(xml, LoadOptions.None);
        manga |= document.Descendants().Any(element => element.Name.LocalName == "manga");
        var rows = document.Descendants().Where(element => element.Name.LocalName is "anime" or "manga");
        return rows.Select(element =>
        {
            string? Get(string name) => element.Elements().FirstOrDefault(child => child.Name.LocalName == name)?.Value;
            var statusCode = ParseInt(Get(manga ? "my_reading_status" : "my_status"));
            var status = statusCode switch { 1 => MediaStatus.InProgress, 2 => MediaStatus.Completed, 3 => MediaStatus.OnHold, 4 => MediaStatus.Dropped, _ => MediaStatus.Planned };
            var score = ParseInt(Get("my_score"));
            var progress = ParseInt(Get(manga ? "my_read_chapters" : "my_watched_episodes"));
            var total = ParseInt(Get(manga ? "chapters" : "episodes"));
            return new ParsedMediaItemDto(Get("series_title") ?? "", manga ? "manga" : "anime", status,
                score is > 0 ? score : null, progress, total, ReleaseYear: ParseInt(Get("start_date")) is null ? null : ParseYear(Get("start_date")),
                ExternalId: Get(manga ? "series_mangadb_id" : "series_animedb_id"), ExternalSource: "mal",
                CurrentVolumes: manga ? ParseInt(Get("my_read_volumes")) : null,
                TotalVolumes: manga ? ParseInt(Get("volumes")) : null);
        }).Where(item => !string.IsNullOrWhiteSpace(item.Title)).ToArray();
    }

    private static int? ParseInt(string? value) => int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var result) ? result : null;
    private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, out var date) ? date.Year : SpanParserExtensions.ParseYearFromDateString(value.AsSpan().Trim());
}
