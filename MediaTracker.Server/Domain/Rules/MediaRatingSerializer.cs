using System.Text.Json;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// The persisted shape of an external rating list. The UI reads <c>score</c> first, so the stored key
/// names are part of the contract and live in exactly one place.
/// </summary>
public static class MediaRatingSerializer
{
    private static readonly JsonSerializerOptions CamelCaseJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static JsonSerializerOptions JsonOptions => CamelCaseJsonOptions;

    public static string Serialize(IEnumerable<RatingSnapshot> ratings) =>
        JsonSerializer.Serialize(
            ratings.Select(rating => new { source = rating.Source, score = rating.Rating, votes = rating.Votes }),
            CamelCaseJsonOptions);
}

public sealed record RatingSnapshot(string Source, double Rating, int? Votes);
