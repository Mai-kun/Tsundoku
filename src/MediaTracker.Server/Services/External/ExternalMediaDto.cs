namespace MediaTracker.Server.Services.External;

public sealed record ExternalMediaDto
{
    public required string ExternalId { get; init; }

    public required string Title { get; init; }

    public string? OriginalTitle { get; init; }

    public string? CoverUrl { get; init; }

    public string? Description { get; init; }

    public int? ReleaseYear { get; init; }

    public required string Type { get; init; }

    public string? Author { get; init; }

    public string? Studio { get; init; }

    public int? TotalCount { get; init; }

    public string? Platform { get; init; }
}
