using System.Text.Json;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// The persisted shape of an external rating list. The UI reads <c>score</c> first, so the stored key
/// names are part of the contract and live in exactly one place.
/// </summary>
public static class MediaRatingSerializer
{
    /// <summary>The stored row shape: lowercase <c>source/score/votes</c> keys under the camelCase policy.</summary>
    internal sealed record MediaRatingRow(string Source, double Score, int? Votes);

    /// <summary>
    /// Reading needs case-insensitive matching, writing does not. The payload is camelCase, and
    /// <see cref="JsonSerializer"/> does not match "source" to a `Source` property by default, so a
    /// plain read silently produced rows whose source was null.
    /// </summary>
    public static JsonSerializerOptions ReadOptions { get; } =
        new(AppJsonSerializerContext.Default.Options) { PropertyNameCaseInsensitive = true };

    public static string Serialize(IEnumerable<RatingSnapshot> ratings) =>
        JsonSerializer.Serialize(ratings.Select(rating => new MediaRatingRow(rating.Source, rating.Rating, rating.Votes)).ToList(), AppJsonSerializerContext.Default.ListMediaRatingRow);
}

public sealed record RatingSnapshot(string Source, double Rating, int? Votes);
