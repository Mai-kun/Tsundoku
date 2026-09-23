using MediaTracker.Server.Services.External;

namespace MediaTracker.Server.Endpoints;

public static class ExternalMediaEndpoints
{
    private static readonly string[] SupportedTypes = ["game", "movie", "tvshow", "anime", "manga", "book"];

    public static IEndpointRouteBuilder MapExternalMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/external");

        group.MapGet("/search", SearchExternalMedia);

        return app;
    }

    private static async Task<IResult> SearchExternalMedia(
        string? type,
        string? query,
        MetadataAggregatorService aggregator,
        CancellationToken ct)
    {
        var normalizedType = type?.Trim().ToLowerInvariant() ?? string.Empty;

        var errors = new Dictionary<string, string[]>();

        if (!SupportedTypes.Contains(normalizedType))
        {
            errors["type"] = [$"Type must be one of: {string.Join(", ", SupportedTypes)}."];
        }

        if (string.IsNullOrWhiteSpace(query) || query.Trim().Length < 2)
        {
            errors["query"] = ["Query must contain at least 2 characters."];
        }

        if (errors.Count > 0)
        {
            return Results.ValidationProblem(errors);
        }

        var results = await aggregator.SearchAsync(normalizedType, query, ct);
        return Results.Ok(results);
    }
}
