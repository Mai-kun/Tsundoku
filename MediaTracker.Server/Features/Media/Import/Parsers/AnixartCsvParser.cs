using System.Globalization;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class AnixartCsvParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(
        string csv,
        MediaStatus? unwatchingStatus = MediaStatus.Planned,
        bool createFavoritesList = true)
    {
        var records = CsvHelperMini.ReadRecords(csv).ToList();
        if (records.Count == 0) return [];

        var rawScores = records
            .Select(r => ParseScore(Get(r, "Моя оценка")))
            .Where(s => s.HasValue)
            .Select(s => s!.Value)
            .ToList();

        var is5Scale = rawScores.Count > 0 && rawScores.Max() <= 5;
        var items = new List<ParsedMediaItemDto>(records.Count);

        foreach (var row in records)
        {
            var ruTitle = Get(row, "Русское название");
            var origTitle = Get(row, "Оригинальное название");
            var altTitle = Get(row, "Альтернативные названия");

            var title = !string.IsNullOrWhiteSpace(ruTitle) ? ruTitle : origTitle;
            if (string.IsNullOrWhiteSpace(title)) continue;

            var (realStatus, isUnwatching) = ParseStatus(Get(row, "Статус просмотра"));
            MediaStatus itemStatus;
            if (isUnwatching)
            {
                if (!unwatchingStatus.HasValue)
                {
                    continue;
                }
                itemStatus = unwatchingStatus.Value;
            }
            else
            {
                itemStatus = realStatus ?? MediaStatus.Planned;
            }

            var romajiTitle = CleanUnspecified(origTitle);
            var originalTitle = CleanUnspecified(altTitle);

            if (string.IsNullOrWhiteSpace(romajiTitle) && !string.IsNullOrWhiteSpace(originalTitle))
            {
                romajiTitle = MediaTitleHelper.ExtractLatinFromTitle(originalTitle);
            }
            if (string.IsNullOrWhiteSpace(romajiTitle))
            {
                romajiTitle = MediaTitleHelper.ExtractLatinFromTitle(title);
            }

            var rawScore = ParseScore(Get(row, "Моя оценка"));
            int? score = null;
            if (rawScore.HasValue)
            {
                score = is5Scale ? rawScore.Value * 2 : rawScore.Value;
            }

            var favVal = Get(row, "Добавлено в избранное");
            var isFavorite = favVal.Equals("Добавлено", StringComparison.OrdinalIgnoreCase) ||
                             favVal.Equals("Да", StringComparison.OrdinalIgnoreCase);

            string? folderName = null;
            bool? isCustomFolder = null;
            if (isFavorite && createFavoritesList)
            {
                folderName = "Избранное";
                isCustomFolder = true;
            }

            items.Add(new ParsedMediaItemDto(
                Title: title,
                Type: "anime",
                Status: itemStatus,
                Score: score,
                ExternalSource: "Anixart",
                RomajiTitle: romajiTitle,
                OriginalTitle: originalTitle,
                FolderName: folderName,
                IsCustomFolder: isCustomFolder));
        }

        return items;
    }

    private static string Get(Dictionary<string, string> row, string key)
    {
        if (row.TryGetValue(key, out var val)) return val.Trim();
        var match = row.FirstOrDefault(kvp => string.Equals(kvp.Key.Trim(), key, StringComparison.OrdinalIgnoreCase));
        return match.Value?.Trim() ?? "";
    }

    private static string? CleanUnspecified(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var trimmed = value.Trim();
        if (trimmed.Equals("Не указано", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("Не указаны", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("-", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        return trimmed;
    }

    private static int? ParseScore(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var trimmed = value.Trim();
        if (trimmed.Equals("Не оценено", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("-", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        return int.TryParse(trimmed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var score) && score > 0 ? score : null;
    }

    private static (MediaStatus? Status, bool IsUnwatching) ParseStatus(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return (null, true);
        var trimmed = value.Trim().ToLowerInvariant();
        return trimmed switch
        {
            "смотрю" => (MediaStatus.InProgress, false),
            "просмотрено" => (MediaStatus.Completed, false),
            "в планах" => (MediaStatus.Planned, false),
            "отложено" => (MediaStatus.OnHold, false),
            "брошено" => (MediaStatus.Dropped, false),
            "не смотрю" => (null, true),
            _ => (null, true),
        };
    }
}
